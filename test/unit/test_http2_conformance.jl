# HTTP/2 Protocol Conformance Tests
# Reference: RFC 7540 - Hypertext Transfer Protocol Version 2 (HTTP/2)

using Test
using gRPCServer

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "HTTP/2 Protocol Conformance" begin

    # =========================================================================
    # Frame Types and Constants
    # =========================================================================

    @testset "Frame types per RFC 7540" begin
        @test gRPCServer.FrameType.DATA == 0x0
        @test gRPCServer.FrameType.HEADERS == 0x1
        @test gRPCServer.FrameType.PRIORITY == 0x2
        @test gRPCServer.FrameType.RST_STREAM == 0x3
        @test gRPCServer.FrameType.SETTINGS == 0x4
        @test gRPCServer.FrameType.PUSH_PROMISE == 0x5
        @test gRPCServer.FrameType.PING == 0x6
        @test gRPCServer.FrameType.GOAWAY == 0x7
        @test gRPCServer.FrameType.WINDOW_UPDATE == 0x8
        @test gRPCServer.FrameType.CONTINUATION == 0x9
    end

    @testset "Frame flags per RFC 7540" begin
        @test gRPCServer.FrameFlags.END_STREAM == 0x1
        @test gRPCServer.FrameFlags.END_HEADERS == 0x4
        @test gRPCServer.FrameFlags.PADDED == 0x8
        @test gRPCServer.FrameFlags.PRIORITY_FLAG == 0x20
        @test gRPCServer.FrameFlags.ACK == 0x1
    end

    @testset "Error codes per RFC 7540 Section 7" begin
        @test gRPCServer.ErrorCode.NO_ERROR == 0x0
        @test gRPCServer.ErrorCode.PROTOCOL_ERROR == 0x1
        @test gRPCServer.ErrorCode.INTERNAL_ERROR == 0x2
        @test gRPCServer.ErrorCode.FLOW_CONTROL_ERROR == 0x3
        @test gRPCServer.ErrorCode.SETTINGS_TIMEOUT == 0x4
        @test gRPCServer.ErrorCode.STREAM_CLOSED == 0x5
        @test gRPCServer.ErrorCode.FRAME_SIZE_ERROR == 0x6
        @test gRPCServer.ErrorCode.REFUSED_STREAM == 0x7
        @test gRPCServer.ErrorCode.CANCEL == 0x8
        @test gRPCServer.ErrorCode.COMPRESSION_ERROR == 0x9
        @test gRPCServer.ErrorCode.CONNECT_ERROR == 0xa
        @test gRPCServer.ErrorCode.ENHANCE_YOUR_CALM == 0xb
        @test gRPCServer.ErrorCode.INADEQUATE_SECURITY == 0xc
        @test gRPCServer.ErrorCode.HTTP_1_1_REQUIRED == 0xd
    end

    @testset "HTTP/2 constants" begin
        @test gRPCServer.FRAME_HEADER_SIZE == 9
        @test gRPCServer.DEFAULT_INITIAL_WINDOW_SIZE == 65535
        @test gRPCServer.DEFAULT_MAX_FRAME_SIZE == 16384
        @test gRPCServer.MIN_MAX_FRAME_SIZE == 16384
        @test gRPCServer.MAX_MAX_FRAME_SIZE == 16777215  # 2^24 - 1
        @test gRPCServer.DEFAULT_HEADER_TABLE_SIZE == 4096
    end

    @testset "Connection preface" begin
        @test gRPCServer.CONNECTION_PREFACE == b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
        @test length(gRPCServer.CONNECTION_PREFACE) == 24
    end

    # =========================================================================
    # Frame Header Encoding/Decoding
    # =========================================================================

    @testset "Frame header encoding" begin
        header = gRPCServer.FrameHeader(100, gRPCServer.FrameType.DATA, 0x01, 5)
        bytes = gRPCServer.encode_frame_header(header)

        @test length(bytes) == 9

        # Length (24 bits, big-endian): 100 = 0x000064
        @test bytes[1] == 0x00
        @test bytes[2] == 0x00
        @test bytes[3] == 0x64

        # Type
        @test bytes[4] == gRPCServer.FrameType.DATA

        # Flags
        @test bytes[5] == 0x01

        # Stream ID (31 bits, big-endian): 5 = 0x00000005
        @test bytes[6] == 0x00
        @test bytes[7] == 0x00
        @test bytes[8] == 0x00
        @test bytes[9] == 0x05
    end

    @testset "Frame header decoding" begin
        # Build a frame header manually
        bytes = UInt8[
            0x00, 0x00, 0x64,  # Length: 100
            0x00,              # Type: DATA
            0x01,              # Flags: END_STREAM
            0x00, 0x00, 0x00, 0x05  # Stream ID: 5
        ]

        header = gRPCServer.decode_frame_header(bytes)

        @test header.length == 100
        @test header.frame_type == gRPCServer.FrameType.DATA
        @test header.flags == 0x01
        @test header.stream_id == 5
    end

    @testset "Frame header round-trip" begin
        original = gRPCServer.FrameHeader(256, gRPCServer.FrameType.HEADERS, 0x05, 1)
        encoded = gRPCServer.encode_frame_header(original)
        decoded = gRPCServer.decode_frame_header(encoded)

        @test decoded.length == original.length
        @test decoded.frame_type == original.frame_type
        @test decoded.flags == original.flags
        @test decoded.stream_id == original.stream_id
    end

    # =========================================================================
    # PING Frame Tests (AC6)
    # =========================================================================

    @testset "AC6: PING frame handling" begin

        @testset "PING receives ACK with same payload" begin
            # Create PING frame
            opaque_data = UInt8[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
            ping = gRPCServer.ping_frame(opaque_data)

            @test ping.header.frame_type == gRPCServer.FrameType.PING
            @test ping.header.stream_id == 0  # PING must be on stream 0
            @test ping.header.length == 8
            @test !gRPCServer.has_flag(ping.header, gRPCServer.FrameFlags.ACK)
            @test ping.payload == opaque_data

            # Create PING ACK with same data
            ping_ack = gRPCServer.ping_frame(opaque_data; ack=true)
            @test gRPCServer.has_flag(ping_ack.header, gRPCServer.FrameFlags.ACK)
            @test ping_ack.payload == opaque_data
        end

        @testset "PING payload must be exactly 8 bytes" begin
            # Valid: 8 bytes
            @test_nowarn gRPCServer.ping_frame(zeros(UInt8, 8))

            # Invalid: not 8 bytes
            @test_throws ArgumentError gRPCServer.ping_frame(zeros(UInt8, 7))
            @test_throws ArgumentError gRPCServer.ping_frame(zeros(UInt8, 9))
        end

        @testset "PING on connection (stream 0)" begin
            conn = gRPCServer.HTTP2Connection()
            conn.state = gRPCServer.ConnectionState.OPEN

            opaque_data = UInt8[0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE]
            ping_frame = gRPCServer.ping_frame(opaque_data)

            response_frames = gRPCServer.process_ping_frame!(conn, ping_frame)

            @test length(response_frames) == 1
            ack_frame = response_frames[1]
            @test ack_frame.header.frame_type == gRPCServer.FrameType.PING
            @test gRPCServer.has_flag(ack_frame.header, gRPCServer.FrameFlags.ACK)
            @test ack_frame.payload == opaque_data
        end

    end

    # =========================================================================
    # GOAWAY Frame Tests (AC6)
    # =========================================================================

    @testset "AC6: GOAWAY frame handling" begin

        @testset "GOAWAY sent on graceful shutdown" begin
            conn = gRPCServer.HTTP2Connection()
            conn.state = gRPCServer.ConnectionState.OPEN
            conn.last_client_stream_id = UInt32(5)

            goaway = gRPCServer.send_goaway(conn, gRPCServer.ErrorCode.NO_ERROR)

            @test goaway.header.frame_type == gRPCServer.FrameType.GOAWAY
            @test goaway.header.stream_id == 0  # GOAWAY is on connection level
            @test conn.goaway_sent
            @test conn.state == gRPCServer.ConnectionState.CLOSING

            # Parse GOAWAY frame
            last_stream_id, error_code, debug_data = gRPCServer.parse_goaway_frame(goaway)
            @test last_stream_id == 5
            @test error_code == gRPCServer.ErrorCode.NO_ERROR
        end

        @testset "GOAWAY with error closes connection" begin
            conn = gRPCServer.HTTP2Connection()
            conn.state = gRPCServer.ConnectionState.OPEN

            goaway = gRPCServer.send_goaway(conn, gRPCServer.ErrorCode.PROTOCOL_ERROR, Vector{UInt8}("protocol error"))

            @test conn.state == gRPCServer.ConnectionState.CLOSED

            last_stream_id, error_code, debug_data = gRPCServer.parse_goaway_frame(goaway)
            @test error_code == gRPCServer.ErrorCode.PROTOCOL_ERROR
            @test String(debug_data) == "protocol error"
        end

        @testset "GOAWAY frame encoding" begin
            goaway = gRPCServer.goaway_frame(10, gRPCServer.ErrorCode.NO_ERROR, UInt8[])

            @test goaway.header.frame_type == gRPCServer.FrameType.GOAWAY
            @test goaway.header.length == 8  # 4 bytes last-stream-id + 4 bytes error code

            # Verify encoding
            payload = goaway.payload
            # Last-Stream-ID: 10 in big-endian
            @test payload[1] == 0x00
            @test payload[2] == 0x00
            @test payload[3] == 0x00
            @test payload[4] == 0x0A
            # Error code: NO_ERROR = 0
            @test payload[5] == 0x00
            @test payload[6] == 0x00
            @test payload[7] == 0x00
            @test payload[8] == 0x00
        end

    end

    # =========================================================================
    # SETTINGS Frame Tests
    # =========================================================================

    @testset "SETTINGS frame handling" begin

        @testset "SETTINGS parameters" begin
            @test gRPCServer.SettingsParameter.HEADER_TABLE_SIZE == 0x1
            @test gRPCServer.SettingsParameter.ENABLE_PUSH == 0x2
            @test gRPCServer.SettingsParameter.MAX_CONCURRENT_STREAMS == 0x3
            @test gRPCServer.SettingsParameter.INITIAL_WINDOW_SIZE == 0x4
            @test gRPCServer.SettingsParameter.MAX_FRAME_SIZE == 0x5
            @test gRPCServer.SettingsParameter.MAX_HEADER_LIST_SIZE == 0x6
        end

        @testset "SETTINGS frame encoding/decoding" begin
            settings = [
                (UInt16(gRPCServer.SettingsParameter.MAX_CONCURRENT_STREAMS), UInt32(100)),
                (UInt16(gRPCServer.SettingsParameter.INITIAL_WINDOW_SIZE), UInt32(65535)),
            ]

            frame = gRPCServer.settings_frame(settings)
            @test frame.header.frame_type == gRPCServer.FrameType.SETTINGS
            @test frame.header.stream_id == 0
            @test frame.header.length == 12  # 2 settings * 6 bytes each

            # Parse back
            parsed = gRPCServer.parse_settings_frame(frame)
            @test length(parsed) == 2
            @test parsed[1] == (UInt16(gRPCServer.SettingsParameter.MAX_CONCURRENT_STREAMS), UInt32(100))
            @test parsed[2] == (UInt16(gRPCServer.SettingsParameter.INITIAL_WINDOW_SIZE), UInt32(65535))
        end

        @testset "SETTINGS ACK" begin
            ack_frame = gRPCServer.settings_frame(; ack=true)

            @test gRPCServer.has_flag(ack_frame.header, gRPCServer.FrameFlags.ACK)
            @test ack_frame.header.length == 0  # ACK must have empty payload
        end

    end

    # =========================================================================
    # WINDOW_UPDATE Frame Tests (AC6: Flow Control)
    # =========================================================================

    @testset "AC6: Flow control - WINDOW_UPDATE" begin

        @testset "WINDOW_UPDATE frame encoding" begin
            frame = gRPCServer.window_update_frame(0, 65535)

            @test frame.header.frame_type == gRPCServer.FrameType.WINDOW_UPDATE
            @test frame.header.length == 4
            @test frame.header.stream_id == 0

            # Parse increment
            increment = gRPCServer.parse_window_update_frame(frame)
            @test increment == 65535
        end

        @testset "WINDOW_UPDATE on stream" begin
            frame = gRPCServer.window_update_frame(5, 32768)

            @test frame.header.stream_id == 5

            increment = gRPCServer.parse_window_update_frame(frame)
            @test increment == 32768
        end

        @testset "WINDOW_UPDATE increment validation" begin
            # Increment must be 1 to 2^31-1
            @test_nowarn gRPCServer.window_update_frame(0, 1)
            @test_nowarn gRPCServer.window_update_frame(0, 2147483647)  # 2^31 - 1

            # Invalid: 0
            @test_throws ArgumentError gRPCServer.window_update_frame(0, 0)
        end

    end

    # =========================================================================
    # RST_STREAM Frame Tests
    # =========================================================================

    @testset "RST_STREAM frame handling" begin

        @testset "RST_STREAM frame encoding" begin
            frame = gRPCServer.rst_stream_frame(5, gRPCServer.ErrorCode.CANCEL)

            @test frame.header.frame_type == gRPCServer.FrameType.RST_STREAM
            @test frame.header.stream_id == 5
            @test frame.header.length == 4

            # Error code: CANCEL = 0x08
            @test frame.payload[1] == 0x00
            @test frame.payload[2] == 0x00
            @test frame.payload[3] == 0x00
            @test frame.payload[4] == 0x08
        end

    end

    # =========================================================================
    # Stream State Machine Tests
    # =========================================================================

    @testset "Stream state machine" begin

        @testset "Stream states per RFC 7540 Section 5.1" begin
            @test gRPCServer.StreamState.IDLE isa gRPCServer.StreamState.T
            @test gRPCServer.StreamState.OPEN isa gRPCServer.StreamState.T
            @test gRPCServer.StreamState.HALF_CLOSED_LOCAL isa gRPCServer.StreamState.T
            @test gRPCServer.StreamState.HALF_CLOSED_REMOTE isa gRPCServer.StreamState.T
            @test gRPCServer.StreamState.CLOSED isa gRPCServer.StreamState.T
        end

        @testset "Stream transitions: IDLE -> OPEN on HEADERS" begin
            stream = gRPCServer.HTTP2Stream(UInt32(1))
            @test stream.state == gRPCServer.StreamState.IDLE

            gRPCServer.receive_headers!(stream, false)  # Not END_STREAM
            @test stream.state == gRPCServer.StreamState.OPEN
        end

        @testset "Stream transitions: IDLE -> HALF_CLOSED_REMOTE on HEADERS with END_STREAM" begin
            stream = gRPCServer.HTTP2Stream(UInt32(1))
            @test stream.state == gRPCServer.StreamState.IDLE

            gRPCServer.receive_headers!(stream, true)  # END_STREAM
            @test stream.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
            @test stream.end_stream_received
        end

        @testset "Stream transitions: OPEN -> HALF_CLOSED_LOCAL on send END_STREAM" begin
            stream = gRPCServer.HTTP2Stream(UInt32(1))
            stream.state = gRPCServer.StreamState.OPEN

            gRPCServer.send_headers!(stream, true)  # END_STREAM
            @test stream.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL
            @test stream.end_stream_sent
        end

        @testset "Client vs server initiated streams" begin
            @test gRPCServer.is_client_initiated(1)
            @test gRPCServer.is_client_initiated(3)
            @test gRPCServer.is_client_initiated(5)
            @test !gRPCServer.is_client_initiated(2)
            @test !gRPCServer.is_client_initiated(4)

            @test gRPCServer.is_server_initiated(2)
            @test gRPCServer.is_server_initiated(4)
            @test !gRPCServer.is_server_initiated(1)
            @test !gRPCServer.is_server_initiated(0)  # Stream 0 is connection-level
        end

    end

    # =========================================================================
    # Connection Preface Processing
    # =========================================================================

    @testset "Connection preface processing" begin

        @testset "Valid connection preface" begin
            conn = gRPCServer.HTTP2Connection()
            @test conn.state == gRPCServer.ConnectionState.PREFACE

            preface = Vector{UInt8}(gRPCServer.CONNECTION_PREFACE)
            success, response_frames = gRPCServer.process_preface(conn, preface)

            @test success
            @test conn.state == gRPCServer.ConnectionState.OPEN
            @test length(response_frames) >= 1
            # First response frame should be SETTINGS
            @test response_frames[1].header.frame_type == gRPCServer.FrameType.SETTINGS
        end

        @testset "Invalid connection preface" begin
            conn = gRPCServer.HTTP2Connection()

            # Preface that matches in length but has wrong content throws error
            invalid_preface = Vector{UInt8}("PRI * HTTP/1.1\r\n\r\nSM\r\n\r\n")
            @test_throws gRPCServer.ConnectionError gRPCServer.process_preface(conn, invalid_preface)

            # Too short preface returns false (not enough data yet)
            conn2 = gRPCServer.HTTP2Connection()
            short_preface = Vector{UInt8}("PRI")
            success, _ = gRPCServer.process_preface(conn2, short_preface)
            @test !success
        end

    end

end  # HTTP/2 Protocol Conformance
