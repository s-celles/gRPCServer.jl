# HTTP/2 stream state machine for gRPCServer.jl
# Per RFC 7540 Section 5: Streams and Multiplexing

# Note: frames.jl must be included before this file

"""
    StreamState

HTTP/2 stream states per RFC 7540 Section 5.1.

# States
- `IDLE`: Stream not yet used
- `RESERVED_LOCAL`: Reserved by local PUSH_PROMISE
- `RESERVED_REMOTE`: Reserved by remote PUSH_PROMISE
- `OPEN`: Active stream for both endpoints
- `HALF_CLOSED_LOCAL`: Local endpoint finished sending
- `HALF_CLOSED_REMOTE`: Remote endpoint finished sending
- `CLOSED`: Stream terminated
"""
module StreamState
    @enum T begin
        IDLE
        RESERVED_LOCAL
        RESERVED_REMOTE
        OPEN
        HALF_CLOSED_LOCAL
        HALF_CLOSED_REMOTE
        CLOSED
    end
end

"""
    StreamError <: Exception

Error related to HTTP/2 stream processing.

# Fields
- `stream_id::UInt32`: Stream that caused the error
- `error_code::UInt32`: HTTP/2 error code
- `message::String`: Error description
"""
struct StreamError <: Exception
    stream_id::UInt32
    error_code::UInt32
    message::String
end

function Base.showerror(io::IO, e::StreamError)
    print(io, "StreamError(stream=$(e.stream_id), code=$(e.error_code)): $(e.message)")
end

"""
    HTTP2Stream

Represents an HTTP/2 stream with state machine and data buffers.

# Fields
- `id::UInt32`: Stream identifier
- `state::StreamState.T`: Current state
- `send_window::Int`: Send flow control window
- `recv_window::Int`: Receive flow control window
- `request_headers::Vector{Tuple{String, String}}`: Request headers
- `response_headers::Vector{Tuple{String, String}}`: Response headers
- `trailers::Vector{Tuple{String, String}}`: Trailing headers
- `data_buffer::IOBuffer`: Accumulated data
- `headers_complete::Bool`: Whether header block is complete
- `end_stream_received::Bool`: Whether END_STREAM has been received
- `end_stream_sent::Bool`: Whether END_STREAM has been sent
- `reset::Bool`: Whether stream has been reset
"""
mutable struct HTTP2Stream
    id::UInt32
    state::StreamState.T
    send_window::Int
    recv_window::Int
    request_headers::Vector{Tuple{String, String}}
    response_headers::Vector{Tuple{String, String}}
    trailers::Vector{Tuple{String, String}}
    data_buffer::IOBuffer
    headers_complete::Bool
    end_stream_received::Bool
    end_stream_sent::Bool
    reset::Bool

    function HTTP2Stream(id::Integer, initial_window_size::Int=DEFAULT_INITIAL_WINDOW_SIZE)
        new(
            UInt32(id),
            StreamState.IDLE,
            initial_window_size,
            initial_window_size,
            Tuple{String, String}[],
            Tuple{String, String}[],
            Tuple{String, String}[],
            IOBuffer(),
            false,
            false,
            false,
            false
        )
    end
end

"""
    is_client_initiated(stream_id::Integer) -> Bool

Check if a stream was initiated by the client (odd-numbered).
"""
function is_client_initiated(stream_id::Integer)::Bool
    return stream_id % 2 == 1
end

"""
    is_server_initiated(stream_id::Integer) -> Bool

Check if a stream was initiated by the server (even-numbered).
"""
function is_server_initiated(stream_id::Integer)::Bool
    return stream_id % 2 == 0 && stream_id > 0
end

"""
    can_send(stream::HTTP2Stream) -> Bool

Check if data can be sent on this stream.
"""
function can_send(stream::HTTP2Stream)::Bool
    return stream.state in (StreamState.OPEN, StreamState.HALF_CLOSED_REMOTE) &&
           !stream.reset && !stream.end_stream_sent
end

"""
    can_receive(stream::HTTP2Stream) -> Bool

Check if data can be received on this stream.
"""
function can_receive(stream::HTTP2Stream)::Bool
    return stream.state in (StreamState.OPEN, StreamState.HALF_CLOSED_LOCAL) &&
           !stream.reset && !stream.end_stream_received
end

"""
    is_closed(stream::HTTP2Stream) -> Bool

Check if the stream is closed.
"""
function is_closed(stream::HTTP2Stream)::Bool
    return stream.state == StreamState.CLOSED || stream.reset
end

# State transition functions

"""
    receive_headers!(stream::HTTP2Stream, end_stream::Bool) -> Nothing

Handle receiving HEADERS frame.
"""
function receive_headers!(stream::HTTP2Stream, end_stream::Bool)
    if stream.state == StreamState.IDLE
        stream.state = end_stream ? StreamState.HALF_CLOSED_REMOTE : StreamState.OPEN
    elseif stream.state == StreamState.RESERVED_REMOTE
        stream.state = end_stream ? StreamState.CLOSED : StreamState.HALF_CLOSED_LOCAL
    elseif stream.state in (StreamState.OPEN, StreamState.HALF_CLOSED_LOCAL)
        # Trailers
        if end_stream
            if stream.state == StreamState.OPEN
                stream.state = StreamState.HALF_CLOSED_REMOTE
            else
                stream.state = StreamState.CLOSED
            end
        end
    else
        throw(StreamError(stream.id, ErrorCode.STREAM_CLOSED,
            "HEADERS received in invalid state: $(stream.state)"))
    end

    if end_stream
        stream.end_stream_received = true
    end
end

"""
    send_headers!(stream::HTTP2Stream, end_stream::Bool) -> Nothing

Handle sending HEADERS frame.
"""
function send_headers!(stream::HTTP2Stream, end_stream::Bool)
    if stream.state == StreamState.IDLE
        stream.state = end_stream ? StreamState.HALF_CLOSED_LOCAL : StreamState.OPEN
    elseif stream.state == StreamState.RESERVED_LOCAL
        stream.state = end_stream ? StreamState.CLOSED : StreamState.HALF_CLOSED_REMOTE
    elseif stream.state in (StreamState.OPEN, StreamState.HALF_CLOSED_REMOTE)
        # Response headers or trailers
        if end_stream
            if stream.state == StreamState.OPEN
                stream.state = StreamState.HALF_CLOSED_LOCAL
            else
                stream.state = StreamState.CLOSED
            end
        end
    else
        throw(StreamError(stream.id, ErrorCode.STREAM_CLOSED,
            "Cannot send HEADERS in state: $(stream.state)"))
    end

    if end_stream
        stream.end_stream_sent = true
    end
end

"""
    receive_data!(stream::HTTP2Stream, data::Vector{UInt8}, end_stream::Bool) -> Nothing

Handle receiving DATA frame.
"""
function receive_data!(stream::HTTP2Stream, data::Vector{UInt8}, end_stream::Bool)
    if !can_receive(stream)
        throw(StreamError(stream.id, ErrorCode.STREAM_CLOSED,
            "DATA received in invalid state: $(stream.state)"))
    end

    # Check flow control
    if length(data) > stream.recv_window
        throw(StreamError(stream.id, ErrorCode.FLOW_CONTROL_ERROR,
            "DATA exceeds flow control window"))
    end

    # Update window and buffer data
    stream.recv_window -= length(data)
    write(stream.data_buffer, data)

    if end_stream
        stream.end_stream_received = true
        if stream.state == StreamState.OPEN
            stream.state = StreamState.HALF_CLOSED_REMOTE
        elseif stream.state == StreamState.HALF_CLOSED_LOCAL
            stream.state = StreamState.CLOSED
        end
    end
end

"""
    send_data!(stream::HTTP2Stream, length::Int, end_stream::Bool) -> Nothing

Handle sending DATA frame (updates state only, doesn't store data).
"""
function send_data!(stream::HTTP2Stream, length::Int, end_stream::Bool)
    if !can_send(stream)
        throw(StreamError(stream.id, ErrorCode.STREAM_CLOSED,
            "Cannot send DATA in state: $(stream.state)"))
    end

    # Check flow control
    if length > stream.send_window
        throw(StreamError(stream.id, ErrorCode.FLOW_CONTROL_ERROR,
            "DATA exceeds flow control window"))
    end

    stream.send_window -= length

    if end_stream
        stream.end_stream_sent = true
        if stream.state == StreamState.OPEN
            stream.state = StreamState.HALF_CLOSED_LOCAL
        elseif stream.state == StreamState.HALF_CLOSED_REMOTE
            stream.state = StreamState.CLOSED
        end
    end
end

"""
    receive_rst_stream!(stream::HTTP2Stream, error_code::UInt32) -> Nothing

Handle receiving RST_STREAM frame.
"""
function receive_rst_stream!(stream::HTTP2Stream, error_code::UInt32)
    stream.state = StreamState.CLOSED
    stream.reset = true
end

"""
    send_rst_stream!(stream::HTTP2Stream, error_code::UInt32) -> Nothing

Handle sending RST_STREAM frame.
"""
function send_rst_stream!(stream::HTTP2Stream, error_code::UInt32)
    stream.state = StreamState.CLOSED
    stream.reset = true
end

"""
    update_send_window!(stream::HTTP2Stream, increment::Int) -> Nothing

Update the send window for flow control.
"""
function update_send_window!(stream::HTTP2Stream, increment::Int)
    new_window = stream.send_window + increment
    if new_window > 2147483647  # 2^31 - 1
        throw(StreamError(stream.id, ErrorCode.FLOW_CONTROL_ERROR,
            "Flow control window overflow"))
    end
    stream.send_window = new_window
end

"""
    update_recv_window!(stream::HTTP2Stream, increment::Int) -> Nothing

Update the receive window for flow control.
"""
function update_recv_window!(stream::HTTP2Stream, increment::Int)
    new_window = stream.recv_window + increment
    if new_window > 2147483647  # 2^31 - 1
        throw(StreamError(stream.id, ErrorCode.FLOW_CONTROL_ERROR,
            "Flow control window overflow"))
    end
    stream.recv_window = new_window
end

"""
    get_data(stream::HTTP2Stream) -> Vector{UInt8}

Get accumulated data from the stream buffer.
"""
function get_data(stream::HTTP2Stream)::Vector{UInt8}
    return take!(stream.data_buffer)
end

"""
    peek_data(stream::HTTP2Stream) -> Vector{UInt8}

Peek at accumulated data without consuming it.
"""
function peek_data(stream::HTTP2Stream)::Vector{UInt8}
    data = take!(stream.data_buffer)
    write(stream.data_buffer, data)
    return data
end

"""
    get_header(stream::HTTP2Stream, name::String) -> Union{String, Nothing}

Get a request header value by name (case-insensitive).
"""
function get_header(stream::HTTP2Stream, name::String)::Union{String, Nothing}
    lowercase_name = lowercase(name)
    for (n, v) in stream.request_headers
        if lowercase(n) == lowercase_name
            return v
        end
    end
    return nothing
end

"""
    get_headers(stream::HTTP2Stream, name::String) -> Vector{String}

Get all request header values for a name (case-insensitive).
"""
function get_headers(stream::HTTP2Stream, name::String)::Vector{String}
    lowercase_name = lowercase(name)
    values = String[]
    for (n, v) in stream.request_headers
        if lowercase(n) == lowercase_name
            push!(values, v)
        end
    end
    return values
end

# gRPC-specific header helpers

"""
    get_method(stream::HTTP2Stream) -> Union{String, Nothing}

Get the :method pseudo-header.
"""
function get_method(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, ":method")
end

"""
    get_path(stream::HTTP2Stream) -> Union{String, Nothing}

Get the :path pseudo-header.
"""
function get_path(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, ":path")
end

"""
    get_authority(stream::HTTP2Stream) -> Union{String, Nothing}

Get the :authority pseudo-header.
"""
function get_authority(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, ":authority")
end

"""
    get_content_type(stream::HTTP2Stream) -> Union{String, Nothing}

Get the content-type header.
"""
function get_content_type(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, "content-type")
end

"""
    get_grpc_encoding(stream::HTTP2Stream) -> Union{String, Nothing}

Get the grpc-encoding header (request compression).
"""
function get_grpc_encoding(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, "grpc-encoding")
end

"""
    get_grpc_accept_encoding(stream::HTTP2Stream) -> Union{String, Nothing}

Get the grpc-accept-encoding header (supported compression codecs).
"""
function get_grpc_accept_encoding(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, "grpc-accept-encoding")
end

"""
    get_grpc_timeout(stream::HTTP2Stream) -> Union{String, Nothing}

Get the grpc-timeout header.
"""
function get_grpc_timeout(stream::HTTP2Stream)::Union{String, Nothing}
    return get_header(stream, "grpc-timeout")
end

"""
    get_metadata(stream::HTTP2Stream) -> Vector{Tuple{String, String}}

Get all custom metadata headers (non-pseudo, non-reserved).
"""
function get_metadata(stream::HTTP2Stream)::Vector{Tuple{String, String}}
    metadata = Tuple{String, String}[]
    reserved = Set(["content-type", "te", "grpc-encoding", "grpc-accept-encoding",
                   "grpc-timeout", "grpc-status", "grpc-message"])

    for (name, value) in stream.request_headers
        if !startswith(name, ":") && !(lowercase(name) in reserved)
            push!(metadata, (name, value))
        end
    end

    return metadata
end

function Base.show(io::IO, stream::HTTP2Stream)
    print(io, "HTTP2Stream(id=$(stream.id), state=$(stream.state)")
    print(io, ", send_window=$(stream.send_window), recv_window=$(stream.recv_window)")
    if stream.reset
        print(io, ", RESET")
    end
    print(io, ")")
end
