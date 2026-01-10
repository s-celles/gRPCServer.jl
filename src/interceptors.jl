# Interceptor support for gRPCServer.jl

"""
    MethodType

Classifies RPC method patterns.

# Values
- `UNARY`: Single request, single response
- `SERVER_STREAMING`: Single request, multiple responses
- `CLIENT_STREAMING`: Multiple requests, single response
- `BIDI_STREAMING`: Multiple requests, multiple responses
"""
module MethodType
    @enum T begin
        UNARY
        SERVER_STREAMING
        CLIENT_STREAMING
        BIDI_STREAMING
    end
end

"""
    MethodInfo

Information about the method being called, provided to interceptors.

# Fields
- `service_name::String`: Fully-qualified service name (e.g., "helloworld.Greeter")
- `method_name::String`: Method name (e.g., "SayHello")
- `method_type::MethodType.T`: RPC pattern type

# Example
```julia
struct LoggingInterceptor <: Interceptor end

function (::LoggingInterceptor)(ctx, request, info::MethodInfo, next)
    @info "Calling" service=info.service_name method=info.method_name
    return next(ctx, request)
end
```
"""
struct MethodInfo
    service_name::String
    method_name::String
    method_type::MethodType.T
end

function Base.show(io::IO, info::MethodInfo)
    print(io, "MethodInfo($(info.service_name)/$(info.method_name), $(info.method_type))")
end

"""
    Interceptor

Abstract type for gRPC interceptors.

Interceptors are callables that wrap handler execution, allowing for
cross-cutting concerns like logging, authentication, metrics, and error handling.

# Required Interface
Subtypes must be callable with signature:
```julia
(interceptor)(ctx::ServerContext, request_or_stream, info::MethodInfo, next::Function) -> response
```

# Arguments
- `ctx::ServerContext`: Request context
- `request_or_stream`: Request message (unary/server streaming) or stream (client/bidi streaming)
- `info::MethodInfo`: Method information
- `next::Function`: Next handler in the chain (call to continue processing)

# Example
```julia
struct AuthInterceptor <: Interceptor
    required_scope::String
end

function (i::AuthInterceptor)(ctx, request, info, next)
    token = get_metadata_string(ctx, "authorization")
    if token === nothing
        throw(GRPCError(StatusCode.UNAUTHENTICATED, "Missing authorization"))
    end

    # Validate token and check scope
    if !validate_token(token, i.required_scope)
        throw(GRPCError(StatusCode.PERMISSION_DENIED, "Insufficient scope"))
    end

    return next(ctx, request)
end
```
"""
abstract type Interceptor end

"""
    LoggingInterceptor <: Interceptor

Built-in interceptor that logs request/response information.

# Fields
- `log_requests::Bool`: Log incoming requests (default: true)
- `log_responses::Bool`: Log responses (default: true)
- `log_errors::Bool`: Log errors (default: true)

# Example
```julia
add_interceptor!(server, LoggingInterceptor())
```
"""
struct LoggingInterceptor <: Interceptor
    log_requests::Bool
    log_responses::Bool
    log_errors::Bool

    LoggingInterceptor(; log_requests::Bool=true, log_responses::Bool=true, log_errors::Bool=true) =
        new(log_requests, log_responses, log_errors)
end

function (i::LoggingInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    start_time = time()

    if i.log_requests
        @info "gRPC request" request_id=ctx.request_id method="$(info.service_name)/$(info.method_name)" peer=ctx.peer.address
    end

    try
        response = next(ctx, request)
        duration_ms = (time() - start_time) * 1000

        if i.log_responses
            @info "gRPC response" request_id=ctx.request_id duration_ms=round(duration_ms, digits=2)
        end

        return response
    catch e
        duration_ms = (time() - start_time) * 1000

        if i.log_errors
            if e isa GRPCError
                @warn "gRPC error" request_id=ctx.request_id code=e.code message=e.message duration_ms=round(duration_ms, digits=2)
            else
                @error "gRPC exception" request_id=ctx.request_id exception=e duration_ms=round(duration_ms, digits=2)
            end
        end

        rethrow()
    end
end

"""
    MetricsInterceptor <: Interceptor

Built-in interceptor that collects request metrics.

# Fields
- `on_request::Function`: Called with (method, request_size) on each request
- `on_response::Function`: Called with (method, status, duration_ms, response_size) on each response

# Example
```julia
metrics = MetricsInterceptor(
    on_request = (method, size) -> increment_counter("grpc_requests", method),
    on_response = (method, status, ms, size) -> record_histogram("grpc_duration", ms, method, status)
)
add_interceptor!(server, metrics)
```
"""
struct MetricsInterceptor <: Interceptor
    on_request::Function
    on_response::Function

    MetricsInterceptor(;
        on_request::Function = (method, size) -> nothing,
        on_response::Function = (method, status, duration_ms, size) -> nothing
    ) = new(on_request, on_response)
end

function (i::MetricsInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    method = "$(info.service_name)/$(info.method_name)"
    start_time = time()

    # Estimate request size (simplified)
    request_size = 0
    if request !== nothing && hasmethod(sizeof, (typeof(request),))
        try
            request_size = sizeof(request)
        catch
        end
    end

    i.on_request(method, request_size)

    status = StatusCode.OK
    response_size = 0

    try
        response = next(ctx, request)
        duration_ms = (time() - start_time) * 1000

        if response !== nothing && hasmethod(sizeof, (typeof(response),))
            try
                response_size = sizeof(response)
            catch
            end
        end

        i.on_response(method, status, duration_ms, response_size)
        return response
    catch e
        duration_ms = (time() - start_time) * 1000

        if e isa GRPCError
            status = e.code
        else
            status = StatusCode.INTERNAL
        end

        i.on_response(method, status, duration_ms, 0)
        rethrow()
    end
end

"""
    TimeoutInterceptor <: Interceptor

Built-in interceptor that enforces request deadlines.

# Fields
- `default_timeout_ms::Union{Int, Nothing}`: Default timeout in milliseconds if none specified

# Example
```julia
add_interceptor!(server, TimeoutInterceptor(default_timeout_ms=30000))  # 30 second default
```
"""
struct TimeoutInterceptor <: Interceptor
    default_timeout_ms::Union{Int, Nothing}

    TimeoutInterceptor(; default_timeout_ms::Union{Int, Nothing}=nothing) =
        new(default_timeout_ms)
end

function (i::TimeoutInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    # Set default deadline if none specified
    if ctx.deadline === nothing && i.default_timeout_ms !== nothing
        ctx.deadline = now() + Millisecond(i.default_timeout_ms)
    end

    # Check if already expired
    remaining = remaining_time(ctx)
    if remaining !== nothing && remaining <= 0
        throw(GRPCError(StatusCode.DEADLINE_EXCEEDED, "Request deadline exceeded before processing"))
    end

    return next(ctx, request)
end

"""
    RecoveryInterceptor <: Interceptor

Built-in interceptor that catches panics and converts them to gRPC errors.

# Fields
- `include_stack_trace::Bool`: Include stack trace in error message (debug mode only)

# Example
```julia
add_interceptor!(server, RecoveryInterceptor(include_stack_trace=true))
```
"""
struct RecoveryInterceptor <: Interceptor
    include_stack_trace::Bool

    RecoveryInterceptor(; include_stack_trace::Bool=false) = new(include_stack_trace)
end

function (i::RecoveryInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    try
        return next(ctx, request)
    catch e
        if e isa GRPCError
            rethrow()  # Pass through GRPCErrors
        end

        # Convert other exceptions to INTERNAL error
        message = if i.include_stack_trace
            io = IOBuffer()
            showerror(io, e, catch_backtrace())
            String(take!(io))
        else
            "Internal server error"
        end

        throw(GRPCError(StatusCode.INTERNAL, message))
    end
end

"""
    InterceptorChain

Manages a chain of interceptors for sequential execution.

# Fields
- `interceptors::Vector{Interceptor}`: Ordered list of interceptors
"""
struct InterceptorChain
    interceptors::Vector{Interceptor}

    InterceptorChain() = new(Interceptor[])
    InterceptorChain(interceptors::Vector{<:Interceptor}) = new(Vector{Interceptor}(interceptors))
end

"""
    add!(chain::InterceptorChain, interceptor::Interceptor)

Add an interceptor to the end of the chain.
"""
function add!(chain::InterceptorChain, interceptor::Interceptor)
    push!(chain.interceptors, interceptor)
end

"""
    prepend!(chain::InterceptorChain, interceptor::Interceptor)

Add an interceptor to the beginning of the chain.
"""
function Base.prepend!(chain::InterceptorChain, interceptor::Interceptor)
    pushfirst!(chain.interceptors, interceptor)
end

"""
    remove!(chain::InterceptorChain, interceptor_type::Type{<:Interceptor})

Remove all interceptors of a given type.
"""
function remove!(chain::InterceptorChain, interceptor_type::Type{<:Interceptor})
    filter!(i -> !(i isa interceptor_type), chain.interceptors)
end

"""
    wrap(chain::InterceptorChain, handler::Function, info::MethodInfo) -> Function

Create a wrapped handler function with all interceptors applied.

Returns a function `(ctx, request) -> response` that executes the interceptor chain.
"""
function wrap(chain::InterceptorChain, handler::Function, info::MethodInfo)::Function
    if isempty(chain.interceptors)
        return handler
    end

    # Build the chain from the inside out
    wrapped = handler

    for interceptor in reverse(chain.interceptors)
        current_handler = wrapped
        wrapped = (ctx, request) -> interceptor(ctx, request, info, current_handler)
    end

    return wrapped
end

"""
    length(chain::InterceptorChain) -> Int

Get the number of interceptors in the chain.
"""
Base.length(chain::InterceptorChain) = length(chain.interceptors)

"""
    isempty(chain::InterceptorChain) -> Bool

Check if the chain has no interceptors.
"""
Base.isempty(chain::InterceptorChain) = isempty(chain.interceptors)

"""
    wrap_streaming(chain::InterceptorChain, handler::Function, info::MethodInfo) -> Function

Create a wrapped handler function for streaming RPCs with all interceptors applied.

For streaming RPCs, the handler signature is `(ctx, stream) -> response_or_nothing`.
Interceptors still receive `(ctx, stream, info, next)` where `stream` is passed as
the second argument instead of `request`.

Returns a function `(ctx, stream) -> response_or_nothing` that executes the interceptor chain.
"""
function wrap_streaming(chain::InterceptorChain, handler::Function, info::MethodInfo)::Function
    if isempty(chain.interceptors)
        return handler
    end

    # Build the chain from the inside out
    # For streaming, the interceptors receive the stream as the "request" argument
    wrapped = handler

    for interceptor in reverse(chain.interceptors)
        current_handler = wrapped
        wrapped = (ctx, stream) -> interceptor(ctx, stream, info, current_handler)
    end

    return wrapped
end

function Base.show(io::IO, chain::InterceptorChain)
    print(io, "InterceptorChain($(length(chain.interceptors)) interceptors)")
end
