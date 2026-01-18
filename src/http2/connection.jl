# HTTP/2 connection management for gRPCServer.jl
# Per RFC 7540: Hypertext Transfer Protocol Version 2 (HTTP/2)

# Note: frames.jl, hpack.jl, stream.jl, and flow_control.jl must be included before this file

"""
    ConnectionState

HTTP/2 connection state.

# States
- `PREFACE`: Waiting for connection preface
- `OPEN`: Connection is active
- `CLOSING`: Sent GOAWAY, finishing pending streams
- `CLOSED`: Connection terminated
"""
module ConnectionState
    @enum T begin
        PREFACE
        OPEN
        CLOSING
        CLOSED
    end
end

"""
    ConnectionError <: Exception

Error related to HTTP/2 connection.

# Fields
- `error_code::UInt32`: HTTP/2 error code
- `message::String`: Error description
"""
struct ConnectionError <: Exception
    error_code::UInt32
    message::String
end

function Base.showerror(io::IO, e::ConnectionError)
    print(io, "ConnectionError(code=$(e.error_code)): $(e.message)")
end

"""
    ConnectionSettings

HTTP/2 connection settings.

# Fields
- `header_table_size::Int`: HPACK dynamic table size
- `enable_push::Bool`: Server push enabled
- `max_concurrent_streams::Int`: Maximum concurrent streams
- `initial_window_size::Int`: Initial stream window size
- `max_frame_size::Int`: Maximum frame payload size
- `max_header_list_size::Int`: Maximum header list size
"""
mutable struct ConnectionSettings
    header_table_size::Int
    enable_push::Bool
    max_concurrent_streams::Int
    initial_window_size::Int
    max_frame_size::Int
    max_header_list_size::Int

    function ConnectionSettings()
        new(
            DEFAULT_HEADER_TABLE_SIZE,
            true,
            100,  # Default for servers
            DEFAULT_INITIAL_WINDOW_SIZE,
            DEFAULT_MAX_FRAME_SIZE,
            typemax(Int)
        )
    end
end

"""
    apply_settings!(settings::ConnectionSettings, params::Vector{Tuple{UInt16, UInt32}})

Apply received SETTINGS parameters.
"""
function apply_settings!(settings::ConnectionSettings, params::Vector{Tuple{UInt16, UInt32}})
    for (param, value) in params
        if param == SettingsParameter.HEADER_TABLE_SIZE
            settings.header_table_size = Int(value)
        elseif param == SettingsParameter.ENABLE_PUSH
            if value > 1
                throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Invalid ENABLE_PUSH value: $value"))
            end
            settings.enable_push = value == 1
        elseif param == SettingsParameter.MAX_CONCURRENT_STREAMS
            settings.max_concurrent_streams = Int(value)
        elseif param == SettingsParameter.INITIAL_WINDOW_SIZE
            if value > 2147483647
                throw(ConnectionError(ErrorCode.FLOW_CONTROL_ERROR, "Invalid INITIAL_WINDOW_SIZE: $value"))
            end
            settings.initial_window_size = Int(value)
        elseif param == SettingsParameter.MAX_FRAME_SIZE
            if value < MIN_MAX_FRAME_SIZE || value > MAX_MAX_FRAME_SIZE
                throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Invalid MAX_FRAME_SIZE: $value"))
            end
            settings.max_frame_size = Int(value)
        elseif param == SettingsParameter.MAX_HEADER_LIST_SIZE
            settings.max_header_list_size = Int(value)
        end
        # Unknown settings are ignored per RFC
    end
end

"""
    to_frame(settings::ConnectionSettings) -> Frame

Create a SETTINGS frame from connection settings.
"""
function to_frame(settings::ConnectionSettings)::Frame
    params = Tuple{UInt16, UInt32}[
        (UInt16(SettingsParameter.HEADER_TABLE_SIZE), UInt32(settings.header_table_size)),
        (UInt16(SettingsParameter.ENABLE_PUSH), UInt32(settings.enable_push ? 1 : 0)),
        (UInt16(SettingsParameter.MAX_CONCURRENT_STREAMS), UInt32(settings.max_concurrent_streams)),
        (UInt16(SettingsParameter.INITIAL_WINDOW_SIZE), UInt32(settings.initial_window_size)),
        (UInt16(SettingsParameter.MAX_FRAME_SIZE), UInt32(settings.max_frame_size)),
    ]

    if settings.max_header_list_size < typemax(Int)
        push!(params, (UInt16(SettingsParameter.MAX_HEADER_LIST_SIZE), UInt32(settings.max_header_list_size)))
    end

    return settings_frame(params)
end

"""
    HTTP2Connection

Manages an HTTP/2 connection.

# Fields
- `state::ConnectionState.T`: Connection state
- `local_settings::ConnectionSettings`: Our settings
- `remote_settings::ConnectionSettings`: Peer's settings
- `streams::Dict{UInt32, HTTP2Stream}`: Active streams
- `hpack_encoder::HPACKEncoder`: HPACK encoder
- `hpack_decoder::HPACKDecoder`: HPACK decoder
- `flow_controller::FlowController`: Flow control manager
- `next_stream_id::UInt32`: Next server-initiated stream ID
- `last_client_stream_id::UInt32`: Highest client stream ID seen
- `goaway_sent::Bool`: Whether GOAWAY has been sent
- `goaway_received::Bool`: Whether GOAWAY has been received
- `pending_settings_ack::Bool`: Whether we're waiting for SETTINGS ACK
- `lock::ReentrantLock`: Thread-safe access
"""
mutable struct HTTP2Connection
    state::ConnectionState.T
    local_settings::ConnectionSettings
    remote_settings::ConnectionSettings
    streams::Dict{UInt32, HTTP2Stream}
    hpack_encoder::HPACKEncoder
    hpack_decoder::HPACKDecoder
    flow_controller::FlowController
    next_stream_id::UInt32
    last_client_stream_id::UInt32
    goaway_sent::Bool
    goaway_received::Bool
    pending_settings_ack::Bool
    lock::ReentrantLock

    function HTTP2Connection(; local_settings::ConnectionSettings=ConnectionSettings())
        new(
            ConnectionState.PREFACE,
            local_settings,
            ConnectionSettings(),
            Dict{UInt32, HTTP2Stream}(),
            HPACKEncoder(local_settings.header_table_size),
            HPACKDecoder(local_settings.header_table_size),
            FlowController(local_settings.initial_window_size),
            2,  # Server-initiated streams are even
            0,
            false,
            false,
            false,
            ReentrantLock()
        )
    end
end

"""
    get_stream(conn::HTTP2Connection, stream_id::UInt32) -> Union{HTTP2Stream, Nothing}

Get a stream by ID.
"""
function get_stream(conn::HTTP2Connection, stream_id::UInt32)::Union{HTTP2Stream, Nothing}
    lock(conn.lock) do
        return get(conn.streams, stream_id, nothing)
    end
end

"""
    can_send_on_stream(conn::HTTP2Connection, stream_id::UInt32) -> Bool

Check if data can be sent on a stream. Returns false if stream doesn't exist
or is not in a sendable state.
"""
function can_send_on_stream(conn::HTTP2Connection, stream_id::UInt32)::Bool
    stream = get_stream(conn, stream_id)
    return stream !== nothing && can_send(stream)
end

"""
    create_stream(conn::HTTP2Connection, stream_id::UInt32) -> HTTP2Stream

Create a new stream.
"""
function create_stream(conn::HTTP2Connection, stream_id::UInt32)::HTTP2Stream
    lock(conn.lock) do
        if haskey(conn.streams, stream_id)
            throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Stream $stream_id already exists"))
        end

        stream = HTTP2Stream(stream_id, conn.local_settings.initial_window_size)
        conn.streams[stream_id] = stream
        create_stream_window!(conn.flow_controller, stream_id)

        return stream
    end
end

"""
    remove_stream(conn::HTTP2Connection, stream_id::UInt32)

Remove a closed stream.
"""
function remove_stream(conn::HTTP2Connection, stream_id::UInt32)
    lock(conn.lock) do
        delete!(conn.streams, stream_id)
        remove_stream_window!(conn.flow_controller, stream_id)
    end
end

"""
    active_stream_count(conn::HTTP2Connection) -> Int

Get the number of active streams.
"""
function active_stream_count(conn::HTTP2Connection)::Int
    lock(conn.lock) do
        return length(conn.streams)
    end
end

"""
    process_preface(conn::HTTP2Connection, data::Vector{UInt8}) -> Tuple{Bool, Vector{Frame}}

Process the client connection preface.
Returns (success, response_frames).
"""
function process_preface(conn::HTTP2Connection, data::Vector{UInt8})::Tuple{Bool, Vector{Frame}}
    if conn.state != ConnectionState.PREFACE
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Unexpected preface"))
    end

    # Check connection preface
    if length(data) < length(CONNECTION_PREFACE)
        return (false, Frame[])  # Need more data
    end

    if data[1:length(CONNECTION_PREFACE)] != CONNECTION_PREFACE
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Invalid connection preface"))
    end

    conn.state = ConnectionState.OPEN

    # Send server preface (SETTINGS frame)
    response_frames = Frame[to_frame(conn.local_settings)]
    conn.pending_settings_ack = true

    return (true, response_frames)
end

"""
    process_frame(conn::HTTP2Connection, frame::Frame) -> Vector{Frame}

Process a received frame and return response frames.
"""
function process_frame(conn::HTTP2Connection, frame::Frame)::Vector{Frame}
    if conn.state == ConnectionState.CLOSED
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Connection is closed"))
    end

    header = frame.header
    response_frames = Frame[]

    if header.frame_type == FrameType.SETTINGS
        append!(response_frames, process_settings_frame!(conn, frame))
    elseif header.frame_type == FrameType.PING
        append!(response_frames, process_ping_frame!(conn, frame))
    elseif header.frame_type == FrameType.GOAWAY
        process_goaway_frame!(conn, frame)
    elseif header.frame_type == FrameType.WINDOW_UPDATE
        process_window_update_frame!(conn, frame)
    elseif header.frame_type == FrameType.HEADERS
        append!(response_frames, process_headers_frame!(conn, frame))
    elseif header.frame_type == FrameType.DATA
        append!(response_frames, process_data_frame!(conn, frame))
    elseif header.frame_type == FrameType.RST_STREAM
        process_rst_stream_frame!(conn, frame)
    elseif header.frame_type == FrameType.CONTINUATION
        append!(response_frames, process_continuation_frame!(conn, frame))
    elseif header.frame_type == FrameType.PRIORITY
        # Priority hints are optional to implement
    elseif header.frame_type == FrameType.PUSH_PROMISE
        # Server doesn't receive PUSH_PROMISE
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Server received PUSH_PROMISE"))
    else
        # Unknown frame types are ignored per RFC
    end

    # Generate flow control updates if needed
    append!(response_frames, generate_window_updates(conn.flow_controller))

    return response_frames
end

"""
    process_settings_frame!(conn::HTTP2Connection, frame::Frame) -> Vector{Frame}

Process a SETTINGS frame.
"""
function process_settings_frame!(conn::HTTP2Connection, frame::Frame)::Vector{Frame}
    if frame.header.stream_id != 0
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "SETTINGS on non-zero stream"))
    end

    if has_flag(frame.header, FrameFlags.ACK)
        if frame.header.length != 0
            throw(ConnectionError(ErrorCode.FRAME_SIZE_ERROR, "SETTINGS ACK with payload"))
        end
        conn.pending_settings_ack = false
        return Frame[]
    end

    # Apply settings
    params = parse_settings_frame(frame)
    old_initial_window_size = conn.remote_settings.initial_window_size
    apply_settings!(conn.remote_settings, params)

    # Update HPACK encoder table size
    set_max_table_size!(conn.hpack_encoder, conn.remote_settings.header_table_size)

    # Adjust flow control windows if initial window size changed
    if conn.remote_settings.initial_window_size != old_initial_window_size
        apply_settings_initial_window_size!(conn.flow_controller, conn.remote_settings.initial_window_size)
    end

    # Send ACK
    return Frame[settings_frame(; ack=true)]
end

"""
    process_ping_frame!(conn::HTTP2Connection, frame::Frame) -> Vector{Frame}

Process a PING frame.
"""
function process_ping_frame!(conn::HTTP2Connection, frame::Frame)::Vector{Frame}
    if frame.header.stream_id != 0
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "PING on non-zero stream"))
    end

    if frame.header.length != 8
        throw(ConnectionError(ErrorCode.FRAME_SIZE_ERROR, "PING payload must be 8 bytes"))
    end

    if has_flag(frame.header, FrameFlags.ACK)
        # This is a PING response
        return Frame[]
    end

    # Send PING ACK with same opaque data
    return Frame[ping_frame(frame.payload; ack=true)]
end

"""
    process_goaway_frame!(conn::HTTP2Connection, frame::Frame)

Process a GOAWAY frame.
"""
function process_goaway_frame!(conn::HTTP2Connection, frame::Frame)
    if frame.header.stream_id != 0
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "GOAWAY on non-zero stream"))
    end

    last_stream_id, error_code, debug_data = parse_goaway_frame(frame)
    conn.goaway_received = true

    # If graceful (NO_ERROR), enter CLOSING state
    if error_code == ErrorCode.NO_ERROR
        conn.state = ConnectionState.CLOSING
    else
        conn.state = ConnectionState.CLOSED
    end
end

"""
    process_window_update_frame!(conn::HTTP2Connection, frame::Frame)

Process a WINDOW_UPDATE frame.
"""
function process_window_update_frame!(conn::HTTP2Connection, frame::Frame)
    if frame.header.length != 4
        throw(ConnectionError(ErrorCode.FRAME_SIZE_ERROR, "WINDOW_UPDATE payload must be 4 bytes"))
    end

    increment = parse_window_update_frame(frame)

    if increment == 0
        if frame.header.stream_id == 0
            throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "WINDOW_UPDATE increment is 0"))
        else
            throw(StreamError(frame.header.stream_id, ErrorCode.PROTOCOL_ERROR, "WINDOW_UPDATE increment is 0"))
        end
    end

    apply_window_update!(conn.flow_controller, frame.header.stream_id, Int(increment))
end

"""
    process_headers_frame!(conn::HTTP2Connection, frame::Frame) -> Vector{Frame}

Process a HEADERS frame.
"""
function process_headers_frame!(conn::HTTP2Connection, frame::Frame)::Vector{Frame}
    stream_id = frame.header.stream_id

    if stream_id == 0
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "HEADERS on stream 0"))
    end

    # Client-initiated streams must be odd
    if !is_client_initiated(stream_id)
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Invalid client stream ID: $stream_id"))
    end

    # Stream ID must be greater than last seen
    if stream_id <= conn.last_client_stream_id
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Stream ID $stream_id <= last seen $(conn.last_client_stream_id)"))
    end

    # Check concurrent streams limit
    if active_stream_count(conn) >= conn.local_settings.max_concurrent_streams
        throw(StreamError(stream_id, ErrorCode.REFUSED_STREAM, "Maximum concurrent streams exceeded"))
    end

    conn.last_client_stream_id = stream_id

    # Create stream
    stream = create_stream(conn, stream_id)

    # Handle padding
    payload = frame.payload
    if has_flag(frame.header, FrameFlags.PADDED)
        if isempty(payload)
            throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Empty padded HEADERS"))
        end
        pad_length = payload[1]
        if pad_length >= frame.header.length
            throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Padding too large"))
        end
        payload = payload[2:(end - pad_length)]
    end

    # Handle priority
    if has_flag(frame.header, FrameFlags.PRIORITY_FLAG)
        if length(payload) < 5
            throw(ConnectionError(ErrorCode.FRAME_SIZE_ERROR, "PRIORITY data too short"))
        end
        # Skip priority data (5 bytes)
        payload = payload[6:end]
    end

    # Decode headers
    end_headers = has_flag(frame.header, FrameFlags.END_HEADERS)
    end_stream = has_flag(frame.header, FrameFlags.END_STREAM)

    if end_headers
        headers = decode_headers(conn.hpack_decoder, payload)
        stream.request_headers = headers
        stream.headers_complete = true
        receive_headers!(stream, end_stream)
    else
        # Need CONTINUATION frames
        write(stream.data_buffer, payload)
    end

    return Frame[]
end

"""
    process_continuation_frame!(conn::HTTP2Connection, frame::Frame) -> Vector{Frame}

Process a CONTINUATION frame.
"""
function process_continuation_frame!(conn::HTTP2Connection, frame::Frame)::Vector{Frame}
    stream_id = frame.header.stream_id

    stream = get_stream(conn, stream_id)
    if stream === nothing
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "CONTINUATION for unknown stream"))
    end

    if stream.headers_complete
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "CONTINUATION after END_HEADERS"))
    end

    # Accumulate header block
    write(stream.data_buffer, frame.payload)

    if has_flag(frame.header, FrameFlags.END_HEADERS)
        header_block = take!(stream.data_buffer)
        headers = decode_headers(conn.hpack_decoder, header_block)
        stream.request_headers = headers
        stream.headers_complete = true
        # Note: END_STREAM is on the HEADERS frame, not CONTINUATION
    end

    return Frame[]
end

"""
    process_data_frame!(conn::HTTP2Connection, frame::Frame) -> Vector{Frame}

Process a DATA frame.
"""
function process_data_frame!(conn::HTTP2Connection, frame::Frame)::Vector{Frame}
    stream_id = frame.header.stream_id

    if stream_id == 0
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "DATA on stream 0"))
    end

    stream = get_stream(conn, stream_id)
    if stream === nothing
        throw(ConnectionError(ErrorCode.STREAM_CLOSED, "DATA for closed stream $stream_id"))
    end

    # Handle padding
    payload = frame.payload
    if has_flag(frame.header, FrameFlags.PADDED)
        if isempty(payload)
            throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Empty padded DATA"))
        end
        pad_length = payload[1]
        if pad_length >= frame.header.length
            throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "Padding too large"))
        end
        payload = payload[2:(end - pad_length)]
    end

    end_stream = has_flag(frame.header, FrameFlags.END_STREAM)
    receive_data!(stream, payload, end_stream)

    return Frame[]
end

"""
    process_rst_stream_frame!(conn::HTTP2Connection, frame::Frame)

Process a RST_STREAM frame.
"""
function process_rst_stream_frame!(conn::HTTP2Connection, frame::Frame)
    stream_id = frame.header.stream_id

    if stream_id == 0
        throw(ConnectionError(ErrorCode.PROTOCOL_ERROR, "RST_STREAM on stream 0"))
    end

    if frame.header.length != 4
        throw(ConnectionError(ErrorCode.FRAME_SIZE_ERROR, "RST_STREAM payload must be 4 bytes"))
    end

    stream = get_stream(conn, stream_id)
    if stream !== nothing
        error_code = (UInt32(frame.payload[1]) << 24) |
                     (UInt32(frame.payload[2]) << 16) |
                     (UInt32(frame.payload[3]) << 8) |
                     UInt32(frame.payload[4])
        receive_rst_stream!(stream, error_code)
    end
end

"""
    send_headers(conn::HTTP2Connection, stream_id::UInt32, headers::Vector{Tuple{String, String}};
                 end_stream::Bool=false) -> Vector{Frame}

Create HEADERS frames for a response.
"""
function send_headers(conn::HTTP2Connection, stream_id::UInt32,
                      headers::Vector{Tuple{String, String}};
                      end_stream::Bool=false)::Vector{Frame}
    header_block = encode_headers(conn.hpack_encoder, headers)

    frames = Frame[]
    max_frame_size = conn.remote_settings.max_frame_size

    if length(header_block) <= max_frame_size
        push!(frames, headers_frame(stream_id, header_block;
                                    end_stream=end_stream, end_headers=true))
    else
        # Split into HEADERS + CONTINUATION frames
        first_chunk = header_block[1:max_frame_size]
        push!(frames, headers_frame(stream_id, first_chunk;
                                    end_stream=end_stream, end_headers=false))

        offset = max_frame_size + 1
        while offset <= length(header_block)
            chunk_end = min(offset + max_frame_size - 1, length(header_block))
            chunk = header_block[offset:chunk_end]
            is_last = chunk_end >= length(header_block)
            push!(frames, continuation_frame(stream_id, chunk; end_headers=is_last))
            offset = chunk_end + 1
        end
    end

    # Update stream state
    stream = get_stream(conn, stream_id)
    if stream !== nothing
        send_headers!(stream, end_stream)
    end

    return frames
end

"""
    send_data(conn::HTTP2Connection, stream_id::UInt32, data::Vector{UInt8};
              end_stream::Bool=false) -> Vector{Frame}

Create DATA frames for response data.
"""
function send_data(conn::HTTP2Connection, stream_id::UInt32, data::Vector{UInt8};
                   end_stream::Bool=false)::Vector{Frame}
    max_frame_size = conn.remote_settings.max_frame_size
    sender = DataSender(conn.flow_controller, max_frame_size)
    frames = send_data_frames(sender, stream_id, data; end_stream=end_stream)

    # Update stream state for each frame
    stream = get_stream(conn, stream_id)
    if stream !== nothing
        for frame in frames
            send_data!(stream, Int(frame.header.length), has_flag(frame.header, FrameFlags.END_STREAM))
        end
    end

    return frames
end

"""
    send_trailers(conn::HTTP2Connection, stream_id::UInt32,
                  trailers::Vector{Tuple{String, String}}) -> Vector{Frame}

Create HEADERS frames for trailers (with END_STREAM).
"""
function send_trailers(conn::HTTP2Connection, stream_id::UInt32,
                       trailers::Vector{Tuple{String, String}})::Vector{Frame}
    return send_headers(conn, stream_id, trailers; end_stream=true)
end

"""
    send_rst_stream(conn::HTTP2Connection, stream_id::UInt32, error_code::Integer) -> Frame

Create a RST_STREAM frame.
"""
function send_rst_stream(conn::HTTP2Connection, stream_id::UInt32, error_code::Integer)::Frame
    stream = get_stream(conn, stream_id)
    if stream !== nothing
        send_rst_stream!(stream, UInt32(error_code))
    end
    return rst_stream_frame(stream_id, error_code)
end

"""
    send_goaway(conn::HTTP2Connection, error_code::Integer, debug_data::Vector{UInt8}=UInt8[]) -> Frame

Create a GOAWAY frame.
"""
function send_goaway(conn::HTTP2Connection, error_code::Integer,
                     debug_data::Vector{UInt8}=UInt8[])::Frame
    conn.goaway_sent = true
    if error_code == ErrorCode.NO_ERROR
        conn.state = ConnectionState.CLOSING
    else
        conn.state = ConnectionState.CLOSED
    end
    return goaway_frame(conn.last_client_stream_id, error_code, debug_data)
end

"""
    is_open(conn::HTTP2Connection) -> Bool

Check if the connection is open.
"""
function is_open(conn::HTTP2Connection)::Bool
    return conn.state in (ConnectionState.OPEN, ConnectionState.CLOSING)
end

"""
    is_closed(conn::HTTP2Connection) -> Bool

Check if the connection is closed.
"""
function is_closed(conn::HTTP2Connection)::Bool
    return conn.state == ConnectionState.CLOSED
end

function Base.show(io::IO, conn::HTTP2Connection)
    print(io, "HTTP2Connection(state=$(conn.state), streams=$(length(conn.streams)))")
end
