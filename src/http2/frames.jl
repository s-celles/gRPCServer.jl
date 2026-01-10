# HTTP/2 frame types and encoding/decoding for gRPCServer.jl
# Per RFC 7540: Hypertext Transfer Protocol Version 2 (HTTP/2)

"""
    FrameType

HTTP/2 frame types per RFC 7540 Section 6.

# Frame Types
- `DATA` (0x0): Conveys payload data
- `HEADERS` (0x1): Opens a stream and carries header block
- `PRIORITY` (0x2): Specifies stream priority
- `RST_STREAM` (0x3): Terminates a stream
- `SETTINGS` (0x4): Configuration parameters
- `PUSH_PROMISE` (0x5): Server push notification
- `PING` (0x6): Connectivity check and RTT measurement
- `GOAWAY` (0x7): Connection shutdown notification
- `WINDOW_UPDATE` (0x8): Flow control window adjustment
- `CONTINUATION` (0x9): Header block continuation
"""
module FrameType
    const DATA = 0x0
    const HEADERS = 0x1
    const PRIORITY = 0x2
    const RST_STREAM = 0x3
    const SETTINGS = 0x4
    const PUSH_PROMISE = 0x5
    const PING = 0x6
    const GOAWAY = 0x7
    const WINDOW_UPDATE = 0x8
    const CONTINUATION = 0x9
end

"""
    FrameFlags

HTTP/2 frame flags per RFC 7540.

# Common Flags
- `END_STREAM` (0x1): Last frame for stream (DATA, HEADERS)
- `END_HEADERS` (0x4): End of header block (HEADERS, PUSH_PROMISE, CONTINUATION)
- `PADDED` (0x8): Frame is padded (DATA, HEADERS, PUSH_PROMISE)
- `PRIORITY` (0x20): Stream dependency info present (HEADERS)
- `ACK` (0x1): Settings/Ping acknowledgment (SETTINGS, PING)
"""
module FrameFlags
    const END_STREAM = 0x1
    const END_HEADERS = 0x4
    const PADDED = 0x8
    const PRIORITY_FLAG = 0x20
    const ACK = 0x1
end

"""
    ErrorCode

HTTP/2 error codes per RFC 7540 Section 7.

# Error Codes
- `NO_ERROR` (0x0): No error
- `PROTOCOL_ERROR` (0x1): Protocol error detected
- `INTERNAL_ERROR` (0x2): Internal error
- `FLOW_CONTROL_ERROR` (0x3): Flow control violation
- `SETTINGS_TIMEOUT` (0x4): Settings not acknowledged
- `STREAM_CLOSED` (0x5): Frame received for closed stream
- `FRAME_SIZE_ERROR` (0x6): Invalid frame size
- `REFUSED_STREAM` (0x7): Stream refused
- `CANCEL` (0x8): Stream cancelled
- `COMPRESSION_ERROR` (0x9): HPACK error
- `CONNECT_ERROR` (0xa): Connection error
- `ENHANCE_YOUR_CALM` (0xb): Excessive load
- `INADEQUATE_SECURITY` (0xc): Underlying transport inadequate
- `HTTP_1_1_REQUIRED` (0xd): Use HTTP/1.1
"""
module ErrorCode
    const NO_ERROR = 0x0
    const PROTOCOL_ERROR = 0x1
    const INTERNAL_ERROR = 0x2
    const FLOW_CONTROL_ERROR = 0x3
    const SETTINGS_TIMEOUT = 0x4
    const STREAM_CLOSED = 0x5
    const FRAME_SIZE_ERROR = 0x6
    const REFUSED_STREAM = 0x7
    const CANCEL = 0x8
    const COMPRESSION_ERROR = 0x9
    const CONNECT_ERROR = 0xa
    const ENHANCE_YOUR_CALM = 0xb
    const INADEQUATE_SECURITY = 0xc
    const HTTP_1_1_REQUIRED = 0xd
end

"""
    SettingsParameter

HTTP/2 SETTINGS parameters per RFC 7540 Section 6.5.2.

# Parameters
- `HEADER_TABLE_SIZE` (0x1): HPACK dynamic table size (default: 4096)
- `ENABLE_PUSH` (0x2): Server push enabled (default: 1)
- `MAX_CONCURRENT_STREAMS` (0x3): Maximum concurrent streams (default: unlimited)
- `INITIAL_WINDOW_SIZE` (0x4): Initial flow control window (default: 65535)
- `MAX_FRAME_SIZE` (0x5): Maximum frame payload size (default: 16384)
- `MAX_HEADER_LIST_SIZE` (0x6): Maximum header list size (default: unlimited)
"""
module SettingsParameter
    const HEADER_TABLE_SIZE = 0x1
    const ENABLE_PUSH = 0x2
    const MAX_CONCURRENT_STREAMS = 0x3
    const INITIAL_WINDOW_SIZE = 0x4
    const MAX_FRAME_SIZE = 0x5
    const MAX_HEADER_LIST_SIZE = 0x6
end

# HTTP/2 Constants
const FRAME_HEADER_SIZE = 9
const DEFAULT_INITIAL_WINDOW_SIZE = 65535
const DEFAULT_MAX_FRAME_SIZE = 16384
const MIN_MAX_FRAME_SIZE = 16384
const MAX_MAX_FRAME_SIZE = 16777215  # 2^24 - 1
const DEFAULT_HEADER_TABLE_SIZE = 4096
const CONNECTION_PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

"""
    FrameHeader

HTTP/2 frame header (9 bytes).

# Fields
- `length::UInt32`: Payload length (24 bits)
- `frame_type::UInt8`: Frame type
- `flags::UInt8`: Frame-specific flags
- `stream_id::UInt32`: Stream identifier (31 bits)
"""
struct FrameHeader
    length::UInt32
    frame_type::UInt8
    flags::UInt8
    stream_id::UInt32

    function FrameHeader(length::Integer, frame_type::Integer, flags::Integer, stream_id::Integer)
        if length > MAX_MAX_FRAME_SIZE
            throw(ArgumentError("Frame length exceeds maximum: $length > $MAX_MAX_FRAME_SIZE"))
        end
        if stream_id < 0
            throw(ArgumentError("Stream ID must be non-negative"))
        end
        new(UInt32(length), UInt8(frame_type), UInt8(flags), UInt32(stream_id) & 0x7FFFFFFF)
    end
end

"""
    encode_frame_header(header::FrameHeader) -> Vector{UInt8}

Encode a frame header to bytes.
"""
function encode_frame_header(header::FrameHeader)::Vector{UInt8}
    bytes = Vector{UInt8}(undef, FRAME_HEADER_SIZE)
    # Length (24 bits, big-endian)
    bytes[1] = UInt8((header.length >> 16) & 0xFF)
    bytes[2] = UInt8((header.length >> 8) & 0xFF)
    bytes[3] = UInt8(header.length & 0xFF)
    # Type (8 bits)
    bytes[4] = header.frame_type
    # Flags (8 bits)
    bytes[5] = header.flags
    # Stream ID (31 bits, big-endian, reserved bit = 0)
    bytes[6] = UInt8((header.stream_id >> 24) & 0x7F)
    bytes[7] = UInt8((header.stream_id >> 16) & 0xFF)
    bytes[8] = UInt8((header.stream_id >> 8) & 0xFF)
    bytes[9] = UInt8(header.stream_id & 0xFF)
    return bytes
end

"""
    decode_frame_header(bytes::AbstractVector{UInt8}) -> FrameHeader

Decode a frame header from bytes.
"""
function decode_frame_header(bytes::AbstractVector{UInt8})::FrameHeader
    if length(bytes) < FRAME_HEADER_SIZE
        throw(ArgumentError("Insufficient bytes for frame header: $(length(bytes)) < $FRAME_HEADER_SIZE"))
    end

    # Length (24 bits, big-endian)
    len = (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])

    # Type (8 bits)
    frame_type = bytes[4]

    # Flags (8 bits)
    flags = bytes[5]

    # Stream ID (31 bits, big-endian, mask out reserved bit)
    stream_id = ((UInt32(bytes[6]) & 0x7F) << 24) |
                (UInt32(bytes[7]) << 16) |
                (UInt32(bytes[8]) << 8) |
                UInt32(bytes[9])

    return FrameHeader(len, frame_type, flags, stream_id)
end

"""
    has_flag(header::FrameHeader, flag::UInt8) -> Bool

Check if a frame header has a specific flag set.
"""
function has_flag(header::FrameHeader, flag::UInt8)::Bool
    return (header.flags & flag) != 0
end

"""
    Frame

HTTP/2 frame consisting of header and payload.

# Fields
- `header::FrameHeader`: Frame header
- `payload::Vector{UInt8}`: Frame payload
"""
struct Frame
    header::FrameHeader
    payload::Vector{UInt8}

    function Frame(header::FrameHeader, payload::Vector{UInt8}=UInt8[])
        if UInt32(length(payload)) != header.length
            throw(ArgumentError("Payload length mismatch: $(length(payload)) != $(header.length)"))
        end
        new(header, payload)
    end
end

"""
    Frame(frame_type, flags, stream_id, payload) -> Frame

Convenience constructor for creating a frame.
"""
function Frame(frame_type::Integer, flags::Integer, stream_id::Integer, payload::Vector{UInt8}=UInt8[])
    header = FrameHeader(length(payload), frame_type, flags, stream_id)
    return Frame(header, payload)
end

"""
    encode_frame(frame::Frame) -> Vector{UInt8}

Encode a complete frame to bytes.
"""
function encode_frame(frame::Frame)::Vector{UInt8}
    header_bytes = encode_frame_header(frame.header)
    return vcat(header_bytes, frame.payload)
end

"""
    decode_frame(bytes::AbstractVector{UInt8}) -> Tuple{Frame, Int}

Decode a complete frame from bytes.
Returns the frame and the number of bytes consumed.
"""
function decode_frame(bytes::AbstractVector{UInt8})::Tuple{Frame, Int}
    if length(bytes) < FRAME_HEADER_SIZE
        throw(ArgumentError("Insufficient bytes for frame: $(length(bytes)) < $FRAME_HEADER_SIZE"))
    end

    header = decode_frame_header(bytes)
    total_size = FRAME_HEADER_SIZE + header.length

    if length(bytes) < total_size
        throw(ArgumentError("Insufficient bytes for frame payload: $(length(bytes)) < $total_size"))
    end

    payload = bytes[(FRAME_HEADER_SIZE + 1):(FRAME_HEADER_SIZE + header.length)]
    return (Frame(header, Vector{UInt8}(payload)), Int(total_size))
end

# Specialized frame constructors

"""
    data_frame(stream_id, data; end_stream=false, padded=false) -> Frame

Create a DATA frame.
"""
function data_frame(stream_id::Integer, data::Vector{UInt8}; end_stream::Bool=false, padded::Bool=false)::Frame
    flags = UInt8(0)
    if end_stream
        flags |= FrameFlags.END_STREAM
    end
    if padded
        flags |= FrameFlags.PADDED
    end
    return Frame(FrameType.DATA, flags, stream_id, data)
end

"""
    headers_frame(stream_id, header_block; end_stream=false, end_headers=true) -> Frame

Create a HEADERS frame.
"""
function headers_frame(stream_id::Integer, header_block::Vector{UInt8};
                       end_stream::Bool=false, end_headers::Bool=true)::Frame
    flags = UInt8(0)
    if end_stream
        flags |= FrameFlags.END_STREAM
    end
    if end_headers
        flags |= FrameFlags.END_HEADERS
    end
    return Frame(FrameType.HEADERS, flags, stream_id, header_block)
end

"""
    settings_frame(settings; ack=false) -> Frame

Create a SETTINGS frame.

# Arguments
- `settings::Vector{Tuple{UInt16, UInt32}}`: List of (parameter, value) pairs
- `ack::Bool`: Whether this is a SETTINGS acknowledgment
"""
function settings_frame(settings::Vector{Tuple{UInt16, UInt32}}=Tuple{UInt16, UInt32}[];
                        ack::Bool=false)::Frame
    flags = ack ? FrameFlags.ACK : UInt8(0)

    if ack
        # ACK frames must have empty payload
        return Frame(FrameType.SETTINGS, flags, 0, UInt8[])
    end

    # Each setting is 6 bytes: 2 bytes identifier + 4 bytes value
    payload = Vector{UInt8}(undef, 6 * length(settings))
    for (i, (param, value)) in enumerate(settings)
        offset = (i - 1) * 6
        # Parameter identifier (16 bits, big-endian)
        payload[offset + 1] = UInt8((param >> 8) & 0xFF)
        payload[offset + 2] = UInt8(param & 0xFF)
        # Value (32 bits, big-endian)
        payload[offset + 3] = UInt8((value >> 24) & 0xFF)
        payload[offset + 4] = UInt8((value >> 16) & 0xFF)
        payload[offset + 5] = UInt8((value >> 8) & 0xFF)
        payload[offset + 6] = UInt8(value & 0xFF)
    end

    return Frame(FrameType.SETTINGS, flags, 0, payload)
end

"""
    parse_settings_frame(frame::Frame) -> Vector{Tuple{UInt16, UInt32}}

Parse settings from a SETTINGS frame payload.
"""
function parse_settings_frame(frame::Frame)::Vector{Tuple{UInt16, UInt32}}
    if frame.header.frame_type != FrameType.SETTINGS
        throw(ArgumentError("Not a SETTINGS frame"))
    end

    if has_flag(frame.header, FrameFlags.ACK)
        return Tuple{UInt16, UInt32}[]
    end

    payload = frame.payload
    if length(payload) % 6 != 0
        throw(ArgumentError("Invalid SETTINGS payload length: $(length(payload))"))
    end

    settings = Vector{Tuple{UInt16, UInt32}}(undef, length(payload) ÷ 6)
    for i in 1:length(settings)
        offset = (i - 1) * 6
        param = (UInt16(payload[offset + 1]) << 8) | UInt16(payload[offset + 2])
        value = (UInt32(payload[offset + 3]) << 24) |
                (UInt32(payload[offset + 4]) << 16) |
                (UInt32(payload[offset + 5]) << 8) |
                UInt32(payload[offset + 6])
        settings[i] = (param, value)
    end

    return settings
end

"""
    ping_frame(opaque_data; ack=false) -> Frame

Create a PING frame.

# Arguments
- `opaque_data::Vector{UInt8}`: 8 bytes of opaque data
- `ack::Bool`: Whether this is a PING acknowledgment
"""
function ping_frame(opaque_data::Vector{UInt8}=zeros(UInt8, 8); ack::Bool=false)::Frame
    if length(opaque_data) != 8
        throw(ArgumentError("PING opaque data must be exactly 8 bytes"))
    end
    flags = ack ? FrameFlags.ACK : UInt8(0)
    return Frame(FrameType.PING, flags, 0, opaque_data)
end

"""
    goaway_frame(last_stream_id, error_code, debug_data=UInt8[]) -> Frame

Create a GOAWAY frame.
"""
function goaway_frame(last_stream_id::Integer, error_code::Integer,
                      debug_data::Vector{UInt8}=UInt8[])::Frame
    payload = Vector{UInt8}(undef, 8 + length(debug_data))
    # Last-Stream-ID (31 bits, big-endian)
    payload[1] = UInt8((last_stream_id >> 24) & 0x7F)
    payload[2] = UInt8((last_stream_id >> 16) & 0xFF)
    payload[3] = UInt8((last_stream_id >> 8) & 0xFF)
    payload[4] = UInt8(last_stream_id & 0xFF)
    # Error Code (32 bits, big-endian)
    payload[5] = UInt8((error_code >> 24) & 0xFF)
    payload[6] = UInt8((error_code >> 16) & 0xFF)
    payload[7] = UInt8((error_code >> 8) & 0xFF)
    payload[8] = UInt8(error_code & 0xFF)
    # Debug data
    payload[9:end] .= debug_data

    return Frame(FrameType.GOAWAY, 0, 0, payload)
end

"""
    parse_goaway_frame(frame::Frame) -> Tuple{UInt32, UInt32, Vector{UInt8}}

Parse a GOAWAY frame.
Returns (last_stream_id, error_code, debug_data).
"""
function parse_goaway_frame(frame::Frame)::Tuple{UInt32, UInt32, Vector{UInt8}}
    if frame.header.frame_type != FrameType.GOAWAY
        throw(ArgumentError("Not a GOAWAY frame"))
    end

    payload = frame.payload
    if length(payload) < 8
        throw(ArgumentError("GOAWAY payload too short: $(length(payload)) < 8"))
    end

    last_stream_id = ((UInt32(payload[1]) & 0x7F) << 24) |
                     (UInt32(payload[2]) << 16) |
                     (UInt32(payload[3]) << 8) |
                     UInt32(payload[4])

    error_code = (UInt32(payload[5]) << 24) |
                 (UInt32(payload[6]) << 16) |
                 (UInt32(payload[7]) << 8) |
                 UInt32(payload[8])

    debug_data = length(payload) > 8 ? payload[9:end] : UInt8[]

    return (last_stream_id, error_code, debug_data)
end

"""
    rst_stream_frame(stream_id, error_code) -> Frame

Create a RST_STREAM frame.
"""
function rst_stream_frame(stream_id::Integer, error_code::Integer)::Frame
    payload = Vector{UInt8}(undef, 4)
    payload[1] = UInt8((error_code >> 24) & 0xFF)
    payload[2] = UInt8((error_code >> 16) & 0xFF)
    payload[3] = UInt8((error_code >> 8) & 0xFF)
    payload[4] = UInt8(error_code & 0xFF)
    return Frame(FrameType.RST_STREAM, 0, stream_id, payload)
end

"""
    window_update_frame(stream_id, increment) -> Frame

Create a WINDOW_UPDATE frame.

# Arguments
- `stream_id::Integer`: Stream ID (0 for connection-level)
- `increment::Integer`: Window size increment (1 to 2^31-1)
"""
function window_update_frame(stream_id::Integer, increment::Integer)::Frame
    if increment < 1 || increment > 2147483647
        throw(ArgumentError("Window increment must be 1 to 2^31-1: $increment"))
    end
    payload = Vector{UInt8}(undef, 4)
    payload[1] = UInt8((increment >> 24) & 0x7F)
    payload[2] = UInt8((increment >> 16) & 0xFF)
    payload[3] = UInt8((increment >> 8) & 0xFF)
    payload[4] = UInt8(increment & 0xFF)
    return Frame(FrameType.WINDOW_UPDATE, 0, stream_id, payload)
end

"""
    parse_window_update_frame(frame::Frame) -> UInt32

Parse a WINDOW_UPDATE frame and return the increment.
"""
function parse_window_update_frame(frame::Frame)::UInt32
    if frame.header.frame_type != FrameType.WINDOW_UPDATE
        throw(ArgumentError("Not a WINDOW_UPDATE frame"))
    end

    payload = frame.payload
    if length(payload) != 4
        throw(ArgumentError("WINDOW_UPDATE payload must be 4 bytes: $(length(payload))"))
    end

    increment = ((UInt32(payload[1]) & 0x7F) << 24) |
                (UInt32(payload[2]) << 16) |
                (UInt32(payload[3]) << 8) |
                UInt32(payload[4])

    return increment
end

"""
    continuation_frame(stream_id, header_block; end_headers=true) -> Frame

Create a CONTINUATION frame.
"""
function continuation_frame(stream_id::Integer, header_block::Vector{UInt8};
                            end_headers::Bool=true)::Frame
    flags = end_headers ? FrameFlags.END_HEADERS : UInt8(0)
    return Frame(FrameType.CONTINUATION, flags, stream_id, header_block)
end

function Base.show(io::IO, header::FrameHeader)
    type_name = if header.frame_type == FrameType.DATA
        "DATA"
    elseif header.frame_type == FrameType.HEADERS
        "HEADERS"
    elseif header.frame_type == FrameType.PRIORITY
        "PRIORITY"
    elseif header.frame_type == FrameType.RST_STREAM
        "RST_STREAM"
    elseif header.frame_type == FrameType.SETTINGS
        "SETTINGS"
    elseif header.frame_type == FrameType.PUSH_PROMISE
        "PUSH_PROMISE"
    elseif header.frame_type == FrameType.PING
        "PING"
    elseif header.frame_type == FrameType.GOAWAY
        "GOAWAY"
    elseif header.frame_type == FrameType.WINDOW_UPDATE
        "WINDOW_UPDATE"
    elseif header.frame_type == FrameType.CONTINUATION
        "CONTINUATION"
    else
        "UNKNOWN($(header.frame_type))"
    end
    print(io, "FrameHeader($type_name, length=$(header.length), flags=0x$(string(header.flags, base=16, pad=2)), stream=$(header.stream_id))")
end

function Base.show(io::IO, frame::Frame)
    print(io, "Frame($(frame.header))")
end
