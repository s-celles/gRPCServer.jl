# Method dispatch and service registration for gRPCServer.jl

using ProtoBuf

"""
    MethodDescriptor

Describes a single RPC method.

# Fields
- `name::String`: Method name (e.g., "SayHello")
- `method_type::MethodType.T`: RPC pattern type
- `input_type::String`: Fully-qualified request message type name
- `output_type::String`: Fully-qualified response message type name
- `handler::Function`: Handler function reference

# Handler Signatures by MethodType
- `UNARY`: `(ctx::ServerContext, request::T) -> R`
- `SERVER_STREAMING`: `(ctx::ServerContext, request::T, stream::ServerStream{R}) -> Nothing`
- `CLIENT_STREAMING`: `(ctx::ServerContext, stream::ClientStream{T}) -> R`
- `BIDI_STREAMING`: `(ctx::ServerContext, stream::BidiStream{T,R}) -> Nothing`

# Example
```julia
method = MethodDescriptor(
    "SayHello",
    MethodType.UNARY,
    "helloworld.HelloRequest",
    "helloworld.HelloReply",
    say_hello
)
```
"""
struct MethodDescriptor
    name::String
    method_type::MethodType.T
    input_type::String
    output_type::String
    handler::Function

    function MethodDescriptor(
        name::String,
        method_type::MethodType.T,
        input_type::String,
        output_type::String,
        handler::Function
    )
        new(name, method_type, input_type, output_type, handler)
    end
end

function Base.show(io::IO, method::MethodDescriptor)
    print(io, "MethodDescriptor($(method.name), $(method.method_type))")
end

"""
    ServiceDescriptor

Describes a gRPC service and its methods.

# Fields
- `name::String`: Fully-qualified service name (e.g., "helloworld.Greeter")
- `methods::Dict{String, MethodDescriptor}`: Methods keyed by name
- `file_descriptor::Union{Vector{UInt8}, Nothing}`: File descriptor for reflection (optional)

# Example
```julia
service = ServiceDescriptor(
    "helloworld.Greeter",
    Dict(
        "SayHello" => MethodDescriptor(
            "SayHello",
            MethodType.UNARY,
            "helloworld.HelloRequest",
            "helloworld.HelloReply",
            say_hello
        )
    ),
    nothing
)
```
"""
struct ServiceDescriptor
    name::String
    methods::Dict{String, MethodDescriptor}
    file_descriptor::Union{Vector{UInt8}, Nothing}

    function ServiceDescriptor(
        name::String,
        methods::Dict{String, MethodDescriptor},
        file_descriptor::Union{Vector{UInt8}, Nothing}=nothing
    )
        new(name, methods, file_descriptor)
    end
end

function Base.show(io::IO, service::ServiceDescriptor)
    print(io, "ServiceDescriptor($(service.name), $(length(service.methods)) methods)")
end

"""
    service_descriptor(service) -> ServiceDescriptor

Get the service descriptor for a service implementation.

This function should be overloaded for custom service types.

# Example
```julia
struct GreeterService end

function gRPCServer.service_descriptor(::GreeterService)
    ServiceDescriptor(
        "helloworld.Greeter",
        Dict(
            "SayHello" => MethodDescriptor(
                "SayHello", MethodType.UNARY,
                "helloworld.HelloRequest", "helloworld.HelloReply",
                say_hello
            )
        ),
        nothing
    )
end
```
"""
function service_descriptor(service)::ServiceDescriptor
    throw(MethodSignatureError(
        "service_descriptor",
        "service_descriptor(service::T) -> ServiceDescriptor",
        "No implementation for $(typeof(service))"
    ))
end

"""
    ServiceRegistry

Registry of services and methods for request routing.

# Fields
- `services::Dict{String, ServiceDescriptor}`: Services by name
- `method_lookup::Dict{String, Tuple{ServiceDescriptor, MethodDescriptor}}`: Method lookup by path
"""
mutable struct ServiceRegistry
    services::Dict{String, ServiceDescriptor}
    method_lookup::Dict{String, Tuple{ServiceDescriptor, MethodDescriptor}}

    ServiceRegistry() = new(
        Dict{String, ServiceDescriptor}(),
        Dict{String, Tuple{ServiceDescriptor, MethodDescriptor}}()
    )
end

"""
    register!(registry::ServiceRegistry, descriptor::ServiceDescriptor)

Register a service in the registry.
"""
function register!(registry::ServiceRegistry, descriptor::ServiceDescriptor)
    if haskey(registry.services, descriptor.name)
        throw(ServiceAlreadyRegisteredError(descriptor.name))
    end

    registry.services[descriptor.name] = descriptor

    # Build method lookup
    for (method_name, method) in descriptor.methods
        path = "/$(descriptor.name)/$(method_name)"
        registry.method_lookup[path] = (descriptor, method)
    end
end

"""
    lookup_method(registry::ServiceRegistry, path::String) -> Union{Tuple{ServiceDescriptor, MethodDescriptor}, Nothing}

Look up a method by its path (e.g., "/helloworld.Greeter/SayHello").
"""
function lookup_method(registry::ServiceRegistry, path::String)::Union{Tuple{ServiceDescriptor, MethodDescriptor}, Nothing}
    return get(registry.method_lookup, path, nothing)
end

"""
    get_service(registry::ServiceRegistry, name::String) -> Union{ServiceDescriptor, Nothing}

Get a service by name.
"""
function get_service(registry::ServiceRegistry, name::String)::Union{ServiceDescriptor, Nothing}
    return get(registry.services, name, nothing)
end

"""
    list_services(registry::ServiceRegistry) -> Vector{String}

List all registered service names.
"""
function list_services(registry::ServiceRegistry)::Vector{String}
    return collect(keys(registry.services))
end

function Base.show(io::IO, registry::ServiceRegistry)
    print(io, "ServiceRegistry($(length(registry.services)) services, $(length(registry.method_lookup)) methods)")
end

"""
    RequestDispatcher

Dispatches incoming requests to the appropriate handler.

# Fields
- `registry::ServiceRegistry`: Service registry
- `interceptor_chain::InterceptorChain`: Global interceptors
- `service_interceptors::Dict{String, InterceptorChain}`: Per-service interceptors
- `debug_mode::Bool`: Include exception details in errors
"""
mutable struct RequestDispatcher
    registry::ServiceRegistry
    interceptor_chain::InterceptorChain
    service_interceptors::Dict{String, InterceptorChain}
    debug_mode::Bool

    RequestDispatcher(; debug_mode::Bool=false) = new(
        ServiceRegistry(),
        InterceptorChain(),
        Dict{String, InterceptorChain}(),
        debug_mode
    )
end

"""
    register_service!(dispatcher::RequestDispatcher, descriptor::ServiceDescriptor)

Register a service with the dispatcher.
"""
function register_service!(dispatcher::RequestDispatcher, descriptor::ServiceDescriptor)
    register!(dispatcher.registry, descriptor)
end

"""
    add_interceptor!(dispatcher::RequestDispatcher, interceptor::Interceptor)

Add a global interceptor.
"""
function add_interceptor!(dispatcher::RequestDispatcher, interceptor::Interceptor)
    add!(dispatcher.interceptor_chain, interceptor)
end

"""
    add_interceptor!(dispatcher::RequestDispatcher, service_name::String, interceptor::Interceptor)

Add a service-specific interceptor.
"""
function add_interceptor!(dispatcher::RequestDispatcher, service_name::String, interceptor::Interceptor)
    if !haskey(dispatcher.service_interceptors, service_name)
        dispatcher.service_interceptors[service_name] = InterceptorChain()
    end
    add!(dispatcher.service_interceptors[service_name], interceptor)
end

"""
    dispatch_unary(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        request_data::Vector{UInt8}
    ) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Dispatch a unary RPC request.
Returns (status_code, status_message, response_data).
"""
function dispatch_unary(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    request_data::Vector{UInt8}
)::Tuple{StatusCode.T, String, Vector{UInt8}}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path", UInt8[])
    end

    service, method = result

    if method.method_type != MethodType.UNARY
        return (StatusCode.UNIMPLEMENTED, "Method is not unary: $(method.name)", UInt8[])
    end

    try
        # Deserialize request
        request = deserialize_message(request_data, method.input_type)

        # Build interceptor chain
        info = MethodInfo(service.name, method.name, method.method_type)
        handler = build_handler_chain(dispatcher, service.name, method.handler, info)

        # Execute handler
        response = handler(ctx, request)

        # Serialize response
        response_data = serialize_message(response)

        return (StatusCode.OK, "", response_data)

    catch e
        return handle_exception(e, dispatcher.debug_mode)
    end
end

"""
    build_handler_chain(dispatcher, service_name, handler, info) -> Function

Build the complete handler chain with interceptors.
"""
function build_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo
)::Function
    # Start with the actual handler
    wrapped = handler

    # Apply service-specific interceptors first (innermost)
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

"""
    handle_exception(e::Exception, debug_mode::Bool) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Convert an exception to a gRPC status response.
"""
function handle_exception(e::Exception, debug_mode::Bool)::Tuple{StatusCode.T, String, Vector{UInt8}}
    if e isa GRPCError
        return (e.code, e.message, UInt8[])
    end

    # Map known exceptions to status codes
    code = exception_to_status_code(e)

    message = if debug_mode
        io = IOBuffer()
        showerror(io, e)
        String(take!(io))
    else
        if code == StatusCode.INTERNAL
            "Internal server error"
        else
            string(e)
        end
    end

    return (code, message, UInt8[])
end

"""
    handle_exception_with_logging(e::Exception, ctx::ServerContext, debug_mode::Bool) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Convert an exception to a gRPC status response with structured logging.
Includes request_id in all error logs for traceability.
"""
function handle_exception_with_logging(e::Exception, ctx::ServerContext, debug_mode::Bool)::Tuple{StatusCode.T, String, Vector{UInt8}}
    if e isa GRPCError
        @warn "gRPC error" request_id=ctx.request_id method=ctx.method code=e.code message=e.message
        return (e.code, e.message, UInt8[])
    end

    # Map known exceptions to status codes
    code = exception_to_status_code(e)

    message = if debug_mode
        io = IOBuffer()
        showerror(io, e)
        String(take!(io))
    else
        if code == StatusCode.INTERNAL
            "Internal server error"
        else
            string(e)
        end
    end

    # Log with structured context
    if code == StatusCode.INTERNAL
        @error "Internal server error" request_id=ctx.request_id method=ctx.method exception=(e, catch_backtrace())
    else
        @warn "Request error" request_id=ctx.request_id method=ctx.method code=code message=message
    end

    return (code, message, UInt8[])
end

"""
    deserialize_message(data::Vector{UInt8}, type_name::String) -> Any

Deserialize a Protocol Buffer message from bytes.
"""
function deserialize_message(data::Vector{UInt8}, type_name::String)
    # Parse gRPC Length-Prefixed Message format
    # Format: 1 byte compressed flag + 4 bytes message length + message
    if length(data) < 5
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Message too short"))
    end

    compressed = data[1] != 0
    msg_length = (UInt32(data[2]) << 24) | (UInt32(data[3]) << 16) |
                 (UInt32(data[4]) << 8) | UInt32(data[5])

    if length(data) < 5 + msg_length
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Message truncated"))
    end

    msg_data = data[6:(5 + msg_length)]

    # Handle compression
    if compressed
        # Decompression would be handled here based on grpc-encoding header
        throw(GRPCError(StatusCode.UNIMPLEMENTED, "Compressed messages not yet supported"))
    end

    # Deserialize using ProtoBuf
    # The actual type resolution would need to be implemented based on the type registry
    # For now, return the raw bytes - the actual implementation would use ProtoBuf.readproto
    try
        io = IOBuffer(msg_data)
        # This is a placeholder - actual implementation needs type resolution
        return msg_data
    catch e
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Failed to deserialize message: $(e)"))
    end
end

"""
    serialize_message(message) -> Vector{UInt8}

Serialize a Protocol Buffer message to bytes in gRPC Length-Prefixed format.
"""
function serialize_message(message)::Vector{UInt8}
    # Serialize message using ProtoBuf
    msg_io = IOBuffer()

    # This is a placeholder - actual implementation would use ProtoBuf.writeproto
    if message isa Vector{UInt8}
        msg_data = message
    else
        # Try to use ProtoBuf serialization
        try
            # writeproto(msg_io, message)
            # msg_data = take!(msg_io)
            # For now, just return empty
            msg_data = UInt8[]
        catch
            msg_data = UInt8[]
        end
    end

    # Build gRPC Length-Prefixed Message
    result = Vector{UInt8}(undef, 5 + length(msg_data))
    result[1] = 0  # Not compressed
    result[2] = UInt8((length(msg_data) >> 24) & 0xFF)
    result[3] = UInt8((length(msg_data) >> 16) & 0xFF)
    result[4] = UInt8((length(msg_data) >> 8) & 0xFF)
    result[5] = UInt8(length(msg_data) & 0xFF)
    result[6:end] .= msg_data

    return result
end

"""
    parse_grpc_path(path::String) -> Tuple{String, String}

Parse a gRPC path into (service_name, method_name).
"""
function parse_grpc_path(path::String)::Tuple{String, String}
    # Path format: /<service>/<method>
    if !startswith(path, "/")
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Invalid path format: $path"))
    end

    parts = split(path[2:end], "/")
    if length(parts) != 2
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Invalid path format: $path"))
    end

    return (String(parts[1]), String(parts[2]))
end

"""
    dispatch_server_streaming(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        request_data::Vector{UInt8},
        send_callback::Function,
        close_callback::Function
    ) -> Tuple{StatusCode.T, String}

Dispatch a server streaming RPC request.
Returns (status_code, status_message) after streaming completes.
"""
function dispatch_server_streaming(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    request_data::Vector{UInt8},
    send_callback::Function,
    close_callback::Function
)::Tuple{StatusCode.T, String}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path")
    end

    service, method = result

    if method.method_type != MethodType.SERVER_STREAMING
        return (StatusCode.UNIMPLEMENTED, "Method is not server streaming: $(method.name)")
    end

    try
        # Deserialize request
        request = deserialize_message(request_data, method.input_type)

        # Create server stream
        stream = ServerStream{Any}(send_callback, close_callback)

        # Build interceptor chain for streaming
        info = MethodInfo(service.name, method.name, method.method_type)

        # For streaming, we wrap the handler differently
        # The handler signature is (ctx, request, stream) -> Nothing
        handler = method.handler

        # Apply interceptors (they receive the request, not the stream)
        wrapped_handler = build_streaming_handler_chain(dispatcher, service.name, handler, info, stream)

        # Execute handler
        wrapped_handler(ctx, request)

        return (StatusCode.OK, "")

    catch e
        code, message, _ = handle_exception(e, dispatcher.debug_mode)
        return (code, message)
    end
end

"""
    dispatch_client_streaming(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        receive_callback::Function,
        is_cancelled_callback::Function
    ) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Dispatch a client streaming RPC request.
Returns (status_code, status_message, response_data).
"""
function dispatch_client_streaming(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    receive_callback::Function,
    is_cancelled_callback::Function
)::Tuple{StatusCode.T, String, Vector{UInt8}}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path", UInt8[])
    end

    service, method = result

    if method.method_type != MethodType.CLIENT_STREAMING
        return (StatusCode.UNIMPLEMENTED, "Method is not client streaming: $(method.name)", UInt8[])
    end

    try
        # Create client stream
        stream = ClientStream{Any}(receive_callback, is_cancelled_callback)

        # Build interceptor chain
        info = MethodInfo(service.name, method.name, method.method_type)

        # For client streaming, handler signature is (ctx, stream) -> response
        handler = method.handler
        wrapped_handler = build_client_streaming_handler_chain(dispatcher, service.name, handler, info)

        # Execute handler - it returns the response
        response = wrapped_handler(ctx, stream)

        # Serialize response
        response_data = serialize_message(response)

        return (StatusCode.OK, "", response_data)

    catch e
        return handle_exception(e, dispatcher.debug_mode)
    end
end

"""
    dispatch_bidi_streaming(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        receive_callback::Function,
        send_callback::Function,
        close_callback::Function,
        is_cancelled_callback::Function
    ) -> Tuple{StatusCode.T, String}

Dispatch a bidirectional streaming RPC request.
Returns (status_code, status_message) after streaming completes.
"""
function dispatch_bidi_streaming(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    receive_callback::Function,
    send_callback::Function,
    close_callback::Function,
    is_cancelled_callback::Function
)::Tuple{StatusCode.T, String}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path")
    end

    service, method = result

    if method.method_type != MethodType.BIDI_STREAMING
        return (StatusCode.UNIMPLEMENTED, "Method is not bidirectional streaming: $(method.name)")
    end

    try
        # Create bidi stream
        stream = BidiStream{Any, Any}(receive_callback, send_callback, close_callback, is_cancelled_callback)

        # Build interceptor chain
        info = MethodInfo(service.name, method.name, method.method_type)

        # For bidi streaming, handler signature is (ctx, stream) -> Nothing
        handler = method.handler
        wrapped_handler = build_bidi_streaming_handler_chain(dispatcher, service.name, handler, info)

        # Execute handler
        wrapped_handler(ctx, stream)

        return (StatusCode.OK, "")

    catch e
        code, message, _ = handle_exception(e, dispatcher.debug_mode)
        return (code, message)
    end
end

"""
    build_streaming_handler_chain(dispatcher, service_name, handler, info, stream) -> Function

Build handler chain for server streaming with interceptors.
Returns a function `(ctx, request) -> Nothing`.
"""
function build_streaming_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo,
    stream::ServerStream
)::Function
    # The actual handler takes (ctx, request, stream)
    # We create a wrapper that captures the stream
    final_handler = (ctx, request) -> begin
        handler(ctx, request, stream)
        return nothing
    end

    # Apply service-specific interceptors first (innermost)
    wrapped = final_handler
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

"""
    build_client_streaming_handler_chain(dispatcher, service_name, handler, info) -> Function

Build handler chain for client streaming with interceptors.
Returns a function `(ctx, stream) -> response`.
"""
function build_client_streaming_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo
)::Function
    # For client streaming, the handler already takes (ctx, stream) -> response
    # We adapt it for the interceptor chain which expects (ctx, request) -> response
    # The "request" in this case is the stream

    wrapped = handler

    # Apply service-specific interceptors first (innermost)
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap_streaming(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap_streaming(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

"""
    build_bidi_streaming_handler_chain(dispatcher, service_name, handler, info) -> Function

Build handler chain for bidirectional streaming with interceptors.
Returns a function `(ctx, stream) -> Nothing`.
"""
function build_bidi_streaming_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo
)::Function
    # For bidi streaming, the handler takes (ctx, stream) -> Nothing
    # Similar to client streaming adaptation

    wrapped = handler

    # Apply service-specific interceptors first (innermost)
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap_streaming(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap_streaming(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

function Base.show(io::IO, dispatcher::RequestDispatcher)
    print(io, "RequestDispatcher($(dispatcher.registry), $(length(dispatcher.interceptor_chain)) interceptors)")
end
