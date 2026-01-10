# Server context for gRPCServer.jl

using UUIDs
using Dates
using Sockets

"""
    PeerInfo

Client connection information.

# Fields
- `address::Union{IPv4, IPv6}`: Client IP address
- `port::Int`: Client port
- `certificate::Union{Vector{UInt8}, Nothing}`: Client certificate for mTLS (DER-encoded)

# Example
```julia
peer = ctx.peer
@info "Client connected from \$(peer.address):\$(peer.port)"
```
"""
struct PeerInfo
    address::Union{IPv4, IPv6}
    port::Int
    certificate::Union{Vector{UInt8}, Nothing}

    PeerInfo(address::Union{IPv4, IPv6}, port::Int;
             certificate::Union{Vector{UInt8}, Nothing}=nothing) =
        new(address, port, certificate)
end

function Base.show(io::IO, peer::PeerInfo)
    print(io, "PeerInfo($(peer.address):$(peer.port)")
    if peer.certificate !== nothing
        print(io, ", mTLS")
    end
    print(io, ")")
end

"""
    ServerContext

Request-scoped context provided to handler functions.

# Fields
- `request_id::UUID`: Unique identifier for this request
- `method::String`: Full method path (e.g., "/helloworld.Greeter/SayHello")
- `authority::String`: Authority from :authority pseudo-header
- `metadata::Dict{String, Union{String, Vector{UInt8}}}`: Request metadata
- `response_headers::Dict{String, Union{String, Vector{UInt8}}}`: Response headers to send
- `trailers::Dict{String, Union{String, Vector{UInt8}}}`: Trailing metadata to send
- `deadline::Union{DateTime, Nothing}`: Request deadline (nothing = no deadline)
- `cancelled::Bool`: Whether the request has been cancelled
- `peer::PeerInfo`: Client connection information
- `trace_context::Union{Vector{UInt8}, Nothing}`: Distributed tracing context

# Example
```julia
function say_hello(ctx::ServerContext, request::HelloRequest)::HelloReply
    @info "Request" id=ctx.request_id method=ctx.method

    # Check cancellation
    if is_cancelled(ctx)
        throw(GRPCError(StatusCode.CANCELLED, "Request cancelled"))
    end

    # Set response header
    set_header!(ctx, "x-request-id", string(ctx.request_id))

    # Check deadline
    remaining = remaining_time(ctx)
    if remaining !== nothing && remaining < 0
        throw(GRPCError(StatusCode.DEADLINE_EXCEEDED, "Deadline exceeded"))
    end

    HelloReply(message = "Hello, \$(request.name)!")
end
```
"""
mutable struct ServerContext
    request_id::UUID
    method::String
    authority::String
    metadata::Dict{String, Union{String, Vector{UInt8}}}
    response_headers::Dict{String, Union{String, Vector{UInt8}}}
    trailers::Dict{String, Union{String, Vector{UInt8}}}
    deadline::Union{DateTime, Nothing}
    cancelled::Bool
    peer::PeerInfo
    trace_context::Union{Vector{UInt8}, Nothing}

    function ServerContext(;
        method::String="",
        authority::String="",
        metadata::Dict{String, Union{String, Vector{UInt8}}}=Dict{String, Union{String, Vector{UInt8}}}(),
        deadline::Union{DateTime, Nothing}=nothing,
        peer::PeerInfo=PeerInfo(IPv4("0.0.0.0"), 0),
        trace_context::Union{Vector{UInt8}, Nothing}=nothing
    )
        new(
            uuid4(),
            method,
            authority,
            metadata,
            Dict{String, Union{String, Vector{UInt8}}}(),
            Dict{String, Union{String, Vector{UInt8}}}(),
            deadline,
            false,
            peer,
            trace_context
        )
    end
end

"""
    set_header!(ctx::ServerContext, key::String, value::String)
    set_header!(ctx::ServerContext, key::String, value::Vector{UInt8})

Set a response header to be sent before the response body.

Headers must be set before the first response message is sent.
Binary headers should have a "-bin" suffix in the key name.

# Example
```julia
set_header!(ctx, "x-custom-header", "custom-value")
set_header!(ctx, "x-binary-data-bin", UInt8[0x01, 0x02, 0x03])
```
"""
function set_header!(ctx::ServerContext, key::String, value::String)
    ctx.response_headers[lowercase(key)] = value
end

function set_header!(ctx::ServerContext, key::String, value::Vector{UInt8})
    ctx.response_headers[lowercase(key)] = value
end

"""
    set_trailer!(ctx::ServerContext, key::String, value::String)
    set_trailer!(ctx::ServerContext, key::String, value::Vector{UInt8})

Set trailing metadata to be sent after the response body.

Trailers are sent at the end of the response stream and can be used
to communicate status information determined during processing.

# Example
```julia
set_trailer!(ctx, "x-processing-time", "150ms")
```
"""
function set_trailer!(ctx::ServerContext, key::String, value::String)
    ctx.trailers[lowercase(key)] = value
end

function set_trailer!(ctx::ServerContext, key::String, value::Vector{UInt8})
    ctx.trailers[lowercase(key)] = value
end

"""
    get_metadata(ctx::ServerContext, key::String) -> Union{String, Vector{UInt8}, Nothing}

Get request metadata by key (case-insensitive).

# Example
```julia
auth = get_metadata(ctx, "authorization")
if auth === nothing
    throw(GRPCError(StatusCode.UNAUTHENTICATED, "Missing authorization"))
end
```
"""
function get_metadata(ctx::ServerContext, key::String)::Union{String, Vector{UInt8}, Nothing}
    return get(ctx.metadata, lowercase(key), nothing)
end

"""
    get_metadata_string(ctx::ServerContext, key::String) -> Union{String, Nothing}

Get request metadata as a string (returns nothing for binary metadata).
"""
function get_metadata_string(ctx::ServerContext, key::String)::Union{String, Nothing}
    value = get_metadata(ctx, key)
    if value isa String
        return value
    end
    return nothing
end

"""
    get_metadata_binary(ctx::ServerContext, key::String) -> Union{Vector{UInt8}, Nothing}

Get request metadata as binary (converts strings to bytes if needed).
"""
function get_metadata_binary(ctx::ServerContext, key::String)::Union{Vector{UInt8}, Nothing}
    value = get_metadata(ctx, key)
    if value isa Vector{UInt8}
        return value
    elseif value isa String
        return Vector{UInt8}(value)
    end
    return nothing
end

"""
    remaining_time(ctx::ServerContext) -> Union{Float64, Nothing}

Get the remaining time until the deadline in seconds.

Returns `nothing` if no deadline is set.
Returns negative value if deadline has passed.

# Example
```julia
remaining = remaining_time(ctx)
if remaining !== nothing && remaining < 0
    throw(GRPCError(StatusCode.DEADLINE_EXCEEDED, "Deadline exceeded"))
end
```
"""
function remaining_time(ctx::ServerContext)::Union{Float64, Nothing}
    if ctx.deadline === nothing
        return nothing
    end
    return Dates.value(ctx.deadline - now()) / 1000.0  # Convert ms to seconds
end

"""
    is_cancelled(ctx::ServerContext) -> Bool

Check if the request has been cancelled by the client.

# Example
```julia
if is_cancelled(ctx)
    throw(GRPCError(StatusCode.CANCELLED, "Request cancelled by client"))
end
```
"""
function is_cancelled(ctx::ServerContext)::Bool
    return ctx.cancelled
end

"""
    cancel!(ctx::ServerContext)

Mark the request as cancelled.
"""
function cancel!(ctx::ServerContext)
    ctx.cancelled = true
end

"""
    parse_grpc_timeout(timeout_str::String) -> Union{DateTime, Nothing}

Parse a gRPC timeout header value to a deadline.

Format: `<value><unit>` where unit is one of:
- `H`: hours
- `M`: minutes
- `S`: seconds
- `m`: milliseconds
- `u`: microseconds
- `n`: nanoseconds

# Example
```julia
deadline = parse_grpc_timeout("30S")  # 30 seconds
deadline = parse_grpc_timeout("500m")  # 500 milliseconds
```
"""
function parse_grpc_timeout(timeout_str::String)::Union{DateTime, Nothing}
    if isempty(timeout_str)
        return nothing
    end

    # Parse value and unit
    unit = timeout_str[end]
    value_str = timeout_str[1:end-1]

    value = tryparse(Int64, value_str)
    if value === nothing || value < 0
        return nothing
    end

    # Convert to milliseconds
    ms = if unit == 'H'
        value * 3600000
    elseif unit == 'M'
        value * 60000
    elseif unit == 'S'
        value * 1000
    elseif unit == 'm'
        value
    elseif unit == 'u'
        value ÷ 1000
    elseif unit == 'n'
        value ÷ 1000000
    else
        return nothing
    end

    return now() + Millisecond(ms)
end

"""
    format_grpc_timeout(deadline::DateTime) -> String

Format a deadline as a gRPC timeout header value.
"""
function format_grpc_timeout(deadline::DateTime)::String
    remaining_ms = max(0, Dates.value(deadline - now()))

    if remaining_ms >= 3600000
        hours = remaining_ms ÷ 3600000
        return "$(hours)H"
    elseif remaining_ms >= 60000
        minutes = remaining_ms ÷ 60000
        return "$(minutes)M"
    elseif remaining_ms >= 1000
        seconds = remaining_ms ÷ 1000
        return "$(seconds)S"
    else
        return "$(remaining_ms)m"
    end
end

"""
    create_context_from_headers(
        headers::Vector{Tuple{String, String}},
        peer::PeerInfo
    ) -> ServerContext

Create a ServerContext from HTTP/2 request headers.
"""
function create_context_from_headers(
    headers::Vector{Tuple{String, String}},
    peer::PeerInfo
)::ServerContext
    metadata = Dict{String, Union{String, Vector{UInt8}}}()
    method = ""
    authority = ""
    deadline = nothing
    trace_context = nothing

    for (name, value) in headers
        name_lower = lowercase(name)

        if name_lower == ":path"
            method = value
        elseif name_lower == ":authority"
            authority = value
        elseif name_lower == "grpc-timeout"
            deadline = parse_grpc_timeout(value)
        elseif name_lower == "grpc-trace-bin"
            # Binary header - should be base64 decoded
            trace_context = try
                base64decode(value)
            catch
                Vector{UInt8}(value)
            end
        elseif !startswith(name_lower, ":")
            # Custom metadata
            if endswith(name_lower, "-bin")
                # Binary metadata - base64 decode
                try
                    metadata[name_lower] = base64decode(value)
                catch
                    metadata[name_lower] = Vector{UInt8}(value)
                end
            else
                metadata[name_lower] = value
            end
        end
    end

    return ServerContext(;
        method=method,
        authority=authority,
        metadata=metadata,
        deadline=deadline,
        peer=peer,
        trace_context=trace_context
    )
end

"""
    get_response_headers(ctx::ServerContext) -> Vector{Tuple{String, String}}

Get response headers formatted for HTTP/2.
"""
function get_response_headers(ctx::ServerContext)::Vector{Tuple{String, String}}
    headers = Tuple{String, String}[]

    for (key, value) in ctx.response_headers
        if value isa Vector{UInt8}
            # Binary header - base64 encode
            push!(headers, (key, base64encode(value)))
        else
            push!(headers, (key, value))
        end
    end

    return headers
end

"""
    get_response_trailers(ctx::ServerContext, status::Int, message::String) -> Vector{Tuple{String, String}}

Get response trailers formatted for HTTP/2, including gRPC status.
"""
function get_response_trailers(ctx::ServerContext, status::Int, message::String)::Vector{Tuple{String, String}}
    trailers = Tuple{String, String}[
        ("grpc-status", string(status)),
    ]

    if !isempty(message)
        # URL-encode the message for grpc-message header
        encoded_message = HTTP_urlencode(message)
        push!(trailers, ("grpc-message", encoded_message))
    end

    for (key, value) in ctx.trailers
        if value isa Vector{UInt8}
            push!(trailers, (key, base64encode(value)))
        else
            push!(trailers, (key, value))
        end
    end

    return trailers
end

# Simple URL encoding for grpc-message
function HTTP_urlencode(s::String)::String
    result = IOBuffer()
    for c in s
        if c in ('a':'z'..., 'A':'Z'..., '0':'9'..., '-', '_', '.', '~')
            write(result, c)
        else
            write(result, '%')
            write(result, uppercase(string(UInt8(c), base=16, pad=2)))
        end
    end
    return String(take!(result))
end

function Base.show(io::IO, ctx::ServerContext)
    print(io, "ServerContext(id=$(ctx.request_id), method=\"$(ctx.method)\"")
    if ctx.deadline !== nothing
        print(io, ", deadline=$(ctx.deadline)")
    end
    if ctx.cancelled
        print(io, ", CANCELLED")
    end
    print(io, ")")
end
