# gRPC stream types for gRPCServer.jl

"""
    ServerStream{T}

Outgoing stream for server streaming and bidirectional RPCs.

Type parameter `T` is the response message type.

# Methods
- `send!(stream, message)`: Send a message
- `close!(stream)`: End the stream

# Example
```julia
function list_features(ctx::ServerContext, request::Rectangle, stream::ServerStream{Feature})
    for feature in find_features(request)
        send!(stream, feature)
    end
end
```
"""
mutable struct ServerStream{T}
    # Callback to send a message
    send_callback::Function
    # Callback to close the stream
    close_callback::Function
    # Whether the stream has been closed
    closed::Bool
    # Message count for tracking
    message_count::Int

    function ServerStream{T}(send_callback::Function, close_callback::Function) where T
        new{T}(send_callback, close_callback, false, 0)
    end
end

"""
    send!(stream::ServerStream{T}, message::T) where T
    send!(stream::ServerStream{T}, message::T; compress::Bool=true) where T

Send a message on the server stream.

# Arguments
- `stream::ServerStream{T}`: The stream to send on
- `message::T`: The message to send
- `compress::Bool=true`: Whether to compress the message (if compression is negotiated)

# Throws
- `StreamCancelledError`: If the stream has been cancelled
- `ArgumentError`: If the stream is closed

# Example
```julia
send!(stream, Feature(name="Feature 1", location=Point(latitude=1, longitude=2)))
```
"""
function send!(stream::ServerStream{T}, message::T; compress::Bool=true) where T
    if stream.closed
        throw(ArgumentError("Cannot send on closed stream"))
    end
    stream.send_callback(message, compress)
    stream.message_count += 1
    return nothing
end

"""
    close!(stream::ServerStream)

Close the server stream, signaling no more messages will be sent.

# Example
```julia
close!(stream)  # Ends the response stream
```
"""
function Base.close(stream::ServerStream)
    if !stream.closed
        stream.close_callback()
        stream.closed = true
    end
    return nothing
end

# Alias for consistency with gRPC terminology
close!(stream::ServerStream) = close(stream)

"""
    is_closed(stream::ServerStream) -> Bool

Check if the stream has been closed.
"""
function is_closed(stream::ServerStream)::Bool
    return stream.closed
end

function Base.show(io::IO, stream::ServerStream{T}) where T
    print(io, "ServerStream{$T}(messages=$(stream.message_count), closed=$(stream.closed))")
end

"""
    ClientStream{T}

Incoming stream for client streaming and bidirectional RPCs.

Type parameter `T` is the request message type.

Implements the Julia iterator interface for use in `for` loops.

# Example
```julia
function record_route(ctx::ServerContext, stream::ClientStream{Point})::RouteSummary
    point_count = 0
    for point in stream
        point_count += 1
        # Process each point
    end
    return RouteSummary(point_count=point_count)
end
```
"""
mutable struct ClientStream{T}
    # Callback to receive the next message (returns nothing when done)
    receive_callback::Function
    # Callback to check cancellation
    is_cancelled_callback::Function
    # Whether we've reached the end
    finished::Bool
    # Message count for tracking
    message_count::Int

    function ClientStream{T}(receive_callback::Function, is_cancelled_callback::Function) where T
        new{T}(receive_callback, is_cancelled_callback, false, 0)
    end
end

# Iterator interface for ClientStream
Base.IteratorSize(::Type{<:ClientStream}) = Base.SizeUnknown()
Base.eltype(::Type{ClientStream{T}}) where T = T

function Base.iterate(stream::ClientStream{T}, state=nothing) where T
    if stream.finished
        return nothing
    end

    if stream.is_cancelled_callback()
        stream.finished = true
        throw(StreamCancelledError("Client stream cancelled"))
    end

    message = stream.receive_callback()

    if message === nothing
        stream.finished = true
        return nothing
    end

    stream.message_count += 1
    return (message::T, nothing)
end

"""
    is_finished(stream::ClientStream) -> Bool

Check if all messages have been received.
"""
function is_finished(stream::ClientStream)::Bool
    return stream.finished
end

"""
    is_cancelled(stream::ClientStream) -> Bool

Check if the stream has been cancelled.
"""
function is_cancelled(stream::ClientStream)::Bool
    return stream.is_cancelled_callback()
end

function Base.show(io::IO, stream::ClientStream{T}) where T
    print(io, "ClientStream{$T}(messages=$(stream.message_count), finished=$(stream.finished))")
end

"""
    BidiStream{T, R}

Bidirectional stream combining input (T) and output (R) streams.

Type parameters:
- `T`: Request message type (incoming)
- `R`: Response message type (outgoing)

Implements the iterator interface for incoming messages and provides
`send!` for outgoing messages.

# Example
```julia
function route_chat(ctx::ServerContext, stream::BidiStream{RouteNote, RouteNote})
    for note in stream  # Iterate incoming messages
        # Echo back each note
        send!(stream, note)
    end
end
```
"""
mutable struct BidiStream{T, R}
    input::ClientStream{T}
    output::ServerStream{R}

    function BidiStream{T, R}(
        receive_callback::Function,
        send_callback::Function,
        close_callback::Function,
        is_cancelled_callback::Function
    ) where {T, R}
        input = ClientStream{T}(receive_callback, is_cancelled_callback)
        output = ServerStream{R}(send_callback, close_callback)
        new{T, R}(input, output)
    end
end

# Iterator interface for BidiStream (delegates to input)
Base.IteratorSize(::Type{<:BidiStream}) = Base.SizeUnknown()
Base.eltype(::Type{BidiStream{T, R}}) where {T, R} = T

function Base.iterate(stream::BidiStream{T, R}, state=nothing) where {T, R}
    return iterate(stream.input, state)
end

"""
    send!(stream::BidiStream{T, R}, message::R) where {T, R}
    send!(stream::BidiStream{T, R}, message::R; compress::Bool=true) where {T, R}

Send a message on the bidirectional stream.

# Example
```julia
send!(stream, RouteNote(message="Hello", location=point))
```
"""
function send!(stream::BidiStream{T, R}, message::R; compress::Bool=true) where {T, R}
    send!(stream.output, message; compress=compress)
end

"""
    close!(stream::BidiStream)

Close the output side of the bidirectional stream.
"""
function close!(stream::BidiStream)
    close!(stream.output)
end

function Base.close(stream::BidiStream)
    close(stream.output)
end

"""
    is_input_finished(stream::BidiStream) -> Bool

Check if all input messages have been received.
"""
function is_input_finished(stream::BidiStream)::Bool
    return is_finished(stream.input)
end

"""
    is_output_closed(stream::BidiStream) -> Bool

Check if the output stream has been closed.
"""
function is_output_closed(stream::BidiStream)::Bool
    return is_closed(stream.output)
end

"""
    is_cancelled(stream::BidiStream) -> Bool

Check if the stream has been cancelled.
"""
function is_cancelled(stream::BidiStream)::Bool
    return is_cancelled(stream.input)
end

function Base.show(io::IO, stream::BidiStream{T, R}) where {T, R}
    print(io, "BidiStream{$T, $R}(")
    print(io, "input=$(stream.input.message_count) msgs, ")
    print(io, "output=$(stream.output.message_count) msgs")
    print(io, ")")
end

# Stream factory functions for internal use

"""
    create_server_stream(send_callback, close_callback, ::Type{T}) where T

Create a ServerStream with the given callbacks.
Internal use only.
"""
function create_server_stream(
    send_callback::Function,
    close_callback::Function,
    ::Type{T}
) where T
    return ServerStream{T}(send_callback, close_callback)
end

"""
    create_client_stream(receive_callback, is_cancelled_callback, ::Type{T}) where T

Create a ClientStream with the given callbacks.
Internal use only.
"""
function create_client_stream(
    receive_callback::Function,
    is_cancelled_callback::Function,
    ::Type{T}
) where T
    return ClientStream{T}(receive_callback, is_cancelled_callback)
end

"""
    create_bidi_stream(
        receive_callback,
        send_callback,
        close_callback,
        is_cancelled_callback,
        ::Type{T},
        ::Type{R}
    ) where {T, R}

Create a BidiStream with the given callbacks.
Internal use only.
"""
function create_bidi_stream(
    receive_callback::Function,
    send_callback::Function,
    close_callback::Function,
    is_cancelled_callback::Function,
    ::Type{T},
    ::Type{R}
) where {T, R}
    return BidiStream{T, R}(receive_callback, send_callback, close_callback, is_cancelled_callback)
end
