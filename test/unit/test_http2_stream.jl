# Unit tests for HTTP/2 stream state machine

using Test
using gRPCServer

@testset "HTTP/2 Stream Unit Tests" begin
    @testset "StreamState Enum" begin
        @test gRPCServer.StreamState.IDLE isa gRPCServer.StreamState.T
        @test gRPCServer.StreamState.OPEN isa gRPCServer.StreamState.T
        @test gRPCServer.StreamState.HALF_CLOSED_LOCAL isa gRPCServer.StreamState.T
        @test gRPCServer.StreamState.HALF_CLOSED_REMOTE isa gRPCServer.StreamState.T
        @test gRPCServer.StreamState.CLOSED isa gRPCServer.StreamState.T
        @test gRPCServer.StreamState.RESERVED_LOCAL isa gRPCServer.StreamState.T
        @test gRPCServer.StreamState.RESERVED_REMOTE isa gRPCServer.StreamState.T
    end

    @testset "StreamError Exception" begin
        err = gRPCServer.StreamError(UInt32(1), UInt32(2), "Test error")
        @test err isa Exception
        @test err.stream_id == 1
        @test err.error_code == 2
        @test err.message == "Test error"

        # Test showerror
        io = IOBuffer()
        showerror(io, err)
        output = String(take!(io))
        @test occursin("StreamError", output)
        @test occursin("stream=1", output)
        @test occursin("code=2", output)
        @test occursin("Test error", output)
    end

    @testset "HTTP2Stream Creation" begin
        stream = gRPCServer.HTTP2Stream(1)
        @test stream.id == 1
        @test stream.state == gRPCServer.StreamState.IDLE
        @test stream.send_window == gRPCServer.DEFAULT_INITIAL_WINDOW_SIZE
        @test stream.recv_window == gRPCServer.DEFAULT_INITIAL_WINDOW_SIZE
        @test isempty(stream.request_headers)
        @test isempty(stream.response_headers)
        @test isempty(stream.trailers)
        @test !stream.headers_complete
        @test !stream.end_stream_received
        @test !stream.end_stream_sent
        @test !stream.reset

        # Custom window size
        stream2 = gRPCServer.HTTP2Stream(3, 1000)
        @test stream2.send_window == 1000
        @test stream2.recv_window == 1000
    end

    @testset "Stream ID Classification" begin
        # Client-initiated streams are odd
        @test gRPCServer.is_client_initiated(1) == true
        @test gRPCServer.is_client_initiated(3) == true
        @test gRPCServer.is_client_initiated(101) == true
        @test gRPCServer.is_client_initiated(2) == false
        @test gRPCServer.is_client_initiated(0) == false

        # Server-initiated streams are even (and > 0)
        @test gRPCServer.is_server_initiated(2) == true
        @test gRPCServer.is_server_initiated(4) == true
        @test gRPCServer.is_server_initiated(100) == true
        @test gRPCServer.is_server_initiated(1) == false
        @test gRPCServer.is_server_initiated(0) == false
    end

    @testset "can_send and can_receive" begin
        stream = gRPCServer.HTTP2Stream(1)

        # IDLE state - cannot send or receive
        @test gRPCServer.can_send(stream) == false
        @test gRPCServer.can_receive(stream) == false

        # Transition to OPEN
        gRPCServer.receive_headers!(stream, false)
        @test stream.state == gRPCServer.StreamState.OPEN
        @test gRPCServer.can_send(stream) == true
        @test gRPCServer.can_receive(stream) == true

        # Transition to HALF_CLOSED_REMOTE
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_headers!(stream2, true)
        @test stream2.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        @test gRPCServer.can_send(stream2) == true
        @test gRPCServer.can_receive(stream2) == false

        # Transition to HALF_CLOSED_LOCAL
        stream3 = gRPCServer.HTTP2Stream(5)
        gRPCServer.receive_headers!(stream3, false)
        gRPCServer.send_headers!(stream3, true)
        @test stream3.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL
        @test gRPCServer.can_send(stream3) == false
        @test gRPCServer.can_receive(stream3) == true
    end

    @testset "is_closed" begin
        stream = gRPCServer.HTTP2Stream(1)
        @test gRPCServer.is_closed(stream) == false

        # Close via state transition
        gRPCServer.receive_headers!(stream, true)
        gRPCServer.send_headers!(stream, true)
        @test stream.state == gRPCServer.StreamState.CLOSED
        @test gRPCServer.is_closed(stream) == true

        # Close via reset
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_rst_stream!(stream2, UInt32(0))
        @test gRPCServer.is_closed(stream2) == true
    end

    @testset "receive_headers! State Transitions" begin
        # IDLE -> OPEN (no end_stream)
        stream1 = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream1, false)
        @test stream1.state == gRPCServer.StreamState.OPEN
        @test stream1.end_stream_received == false

        # IDLE -> HALF_CLOSED_REMOTE (with end_stream)
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_headers!(stream2, true)
        @test stream2.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        @test stream2.end_stream_received == true

        # OPEN -> HALF_CLOSED_REMOTE (trailers with end_stream)
        stream3 = gRPCServer.HTTP2Stream(5)
        gRPCServer.receive_headers!(stream3, false)
        gRPCServer.receive_headers!(stream3, true)
        @test stream3.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE

        # HALF_CLOSED_LOCAL -> CLOSED (trailers with end_stream)
        stream4 = gRPCServer.HTTP2Stream(7)
        gRPCServer.receive_headers!(stream4, false)
        gRPCServer.send_headers!(stream4, true)
        @test stream4.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL
        gRPCServer.receive_headers!(stream4, true)
        @test stream4.state == gRPCServer.StreamState.CLOSED

        # RESERVED_REMOTE -> HALF_CLOSED_LOCAL (no end_stream)
        stream5 = gRPCServer.HTTP2Stream(9)
        stream5.state = gRPCServer.StreamState.RESERVED_REMOTE
        gRPCServer.receive_headers!(stream5, false)
        @test stream5.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL

        # RESERVED_REMOTE -> CLOSED (with end_stream)
        stream6 = gRPCServer.HTTP2Stream(11)
        stream6.state = gRPCServer.StreamState.RESERVED_REMOTE
        gRPCServer.receive_headers!(stream6, true)
        @test stream6.state == gRPCServer.StreamState.CLOSED

        # Invalid state should throw
        stream_closed = gRPCServer.HTTP2Stream(13)
        stream_closed.state = gRPCServer.StreamState.CLOSED
        @test_throws gRPCServer.StreamError gRPCServer.receive_headers!(stream_closed, false)
    end

    @testset "send_headers! State Transitions" begin
        # IDLE -> OPEN (no end_stream)
        stream1 = gRPCServer.HTTP2Stream(1)
        gRPCServer.send_headers!(stream1, false)
        @test stream1.state == gRPCServer.StreamState.OPEN
        @test stream1.end_stream_sent == false

        # IDLE -> HALF_CLOSED_LOCAL (with end_stream)
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.send_headers!(stream2, true)
        @test stream2.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL
        @test stream2.end_stream_sent == true

        # OPEN -> HALF_CLOSED_LOCAL (response with end_stream)
        stream3 = gRPCServer.HTTP2Stream(5)
        gRPCServer.receive_headers!(stream3, false)
        gRPCServer.send_headers!(stream3, true)
        @test stream3.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL

        # HALF_CLOSED_REMOTE -> CLOSED (response with end_stream)
        stream4 = gRPCServer.HTTP2Stream(7)
        gRPCServer.receive_headers!(stream4, true)
        @test stream4.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        gRPCServer.send_headers!(stream4, true)
        @test stream4.state == gRPCServer.StreamState.CLOSED

        # RESERVED_LOCAL -> HALF_CLOSED_REMOTE (no end_stream)
        stream5 = gRPCServer.HTTP2Stream(9)
        stream5.state = gRPCServer.StreamState.RESERVED_LOCAL
        gRPCServer.send_headers!(stream5, false)
        @test stream5.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE

        # RESERVED_LOCAL -> CLOSED (with end_stream)
        stream6 = gRPCServer.HTTP2Stream(11)
        stream6.state = gRPCServer.StreamState.RESERVED_LOCAL
        gRPCServer.send_headers!(stream6, true)
        @test stream6.state == gRPCServer.StreamState.CLOSED

        # Invalid state should throw
        stream_closed = gRPCServer.HTTP2Stream(13)
        stream_closed.state = gRPCServer.StreamState.CLOSED
        @test_throws gRPCServer.StreamError gRPCServer.send_headers!(stream_closed, false)
    end

    @testset "receive_data!" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)
        @test stream.state == gRPCServer.StreamState.OPEN

        # Receive data without end_stream
        data1 = UInt8[1, 2, 3, 4, 5]
        initial_window = stream.recv_window
        gRPCServer.receive_data!(stream, data1, false)
        @test stream.recv_window == initial_window - length(data1)
        @test stream.state == gRPCServer.StreamState.OPEN
        @test stream.end_stream_received == false

        # Receive data with end_stream
        data2 = UInt8[6, 7, 8]
        gRPCServer.receive_data!(stream, data2, true)
        @test stream.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        @test stream.end_stream_received == true

        # Verify data was buffered
        all_data = gRPCServer.get_data(stream)
        @test all_data == UInt8[1, 2, 3, 4, 5, 6, 7, 8]
    end

    @testset "receive_data! Flow Control Error" begin
        stream = gRPCServer.HTTP2Stream(1, 10)  # Small window
        gRPCServer.receive_headers!(stream, false)

        # Data larger than window should throw
        large_data = UInt8[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        @test_throws gRPCServer.StreamError gRPCServer.receive_data!(stream, large_data, false)
    end

    @testset "receive_data! Invalid State" begin
        stream = gRPCServer.HTTP2Stream(1)
        # IDLE state - cannot receive data
        @test_throws gRPCServer.StreamError gRPCServer.receive_data!(stream, UInt8[1], false)

        # HALF_CLOSED_REMOTE - cannot receive data
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_headers!(stream2, true)
        @test_throws gRPCServer.StreamError gRPCServer.receive_data!(stream2, UInt8[1], false)
    end

    @testset "receive_data! HALF_CLOSED_LOCAL -> CLOSED" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)
        gRPCServer.send_headers!(stream, true)
        @test stream.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL

        gRPCServer.receive_data!(stream, UInt8[1, 2, 3], true)
        @test stream.state == gRPCServer.StreamState.CLOSED
    end

    @testset "send_data!" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)
        @test stream.state == gRPCServer.StreamState.OPEN

        # Send data without end_stream
        initial_window = stream.send_window
        gRPCServer.send_data!(stream, 100, false)
        @test stream.send_window == initial_window - 100
        @test stream.state == gRPCServer.StreamState.OPEN
        @test stream.end_stream_sent == false

        # Send data with end_stream
        gRPCServer.send_data!(stream, 50, true)
        @test stream.state == gRPCServer.StreamState.HALF_CLOSED_LOCAL
        @test stream.end_stream_sent == true
    end

    @testset "send_data! Flow Control Error" begin
        stream = gRPCServer.HTTP2Stream(1, 10)  # Small window
        gRPCServer.receive_headers!(stream, false)

        # Data larger than window should throw
        @test_throws gRPCServer.StreamError gRPCServer.send_data!(stream, 11, false)
    end

    @testset "send_data! Invalid State" begin
        stream = gRPCServer.HTTP2Stream(1)
        # IDLE state - cannot send data
        @test_throws gRPCServer.StreamError gRPCServer.send_data!(stream, 10, false)

        # HALF_CLOSED_LOCAL - cannot send data
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.send_headers!(stream2, true)
        @test_throws gRPCServer.StreamError gRPCServer.send_data!(stream2, 10, false)
    end

    @testset "send_data! HALF_CLOSED_REMOTE -> CLOSED" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, true)
        @test stream.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE

        gRPCServer.send_data!(stream, 100, true)
        @test stream.state == gRPCServer.StreamState.CLOSED
    end

    @testset "RST_STREAM Handling" begin
        # receive_rst_stream!
        stream1 = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream1, false)
        gRPCServer.receive_rst_stream!(stream1, UInt32(8))  # CANCEL
        @test stream1.state == gRPCServer.StreamState.CLOSED
        @test stream1.reset == true

        # send_rst_stream!
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_headers!(stream2, false)
        gRPCServer.send_rst_stream!(stream2, UInt32(2))  # INTERNAL_ERROR
        @test stream2.state == gRPCServer.StreamState.CLOSED
        @test stream2.reset == true
    end

    @testset "Window Updates" begin
        stream = gRPCServer.HTTP2Stream(1, 1000)

        # Update send window
        gRPCServer.update_send_window!(stream, 500)
        @test stream.send_window == 1500

        # Update recv window
        gRPCServer.update_recv_window!(stream, 300)
        @test stream.recv_window == 1300

        # Overflow should throw
        stream2 = gRPCServer.HTTP2Stream(3, 2147483600)
        @test_throws gRPCServer.StreamError gRPCServer.update_send_window!(stream2, 100)
        @test_throws gRPCServer.StreamError gRPCServer.update_recv_window!(stream2, 100)
    end

    @testset "Data Buffer Operations" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)

        # Buffer some data
        gRPCServer.receive_data!(stream, UInt8[1, 2, 3], false)
        gRPCServer.receive_data!(stream, UInt8[4, 5], false)

        # peek_data should not consume
        peeked = gRPCServer.peek_data(stream)
        @test peeked == UInt8[1, 2, 3, 4, 5]

        # Can peek again
        peeked2 = gRPCServer.peek_data(stream)
        @test peeked2 == UInt8[1, 2, 3, 4, 5]

        # get_data consumes the buffer
        data = gRPCServer.get_data(stream)
        @test data == UInt8[1, 2, 3, 4, 5]

        # Buffer is now empty
        @test gRPCServer.get_data(stream) == UInt8[]
    end

    @testset "Header Accessors" begin
        stream = gRPCServer.HTTP2Stream(1)
        stream.request_headers = [
            (":method", "POST"),
            (":path", "/helloworld.Greeter/SayHello"),
            (":authority", "localhost:50051"),
            ("content-type", "application/grpc"),
            ("grpc-encoding", "gzip"),
            ("grpc-accept-encoding", "gzip,identity"),
            ("grpc-timeout", "10S"),
            ("x-custom-header", "value1"),
            ("X-Custom-Header", "value2"),
            ("te", "trailers"),
        ]

        # get_header (case-insensitive)
        @test gRPCServer.get_header(stream, ":method") == "POST"
        @test gRPCServer.get_header(stream, ":METHOD") == "POST"
        @test gRPCServer.get_header(stream, "Content-Type") == "application/grpc"
        @test gRPCServer.get_header(stream, "nonexistent") === nothing

        # get_headers (multiple values)
        custom_values = gRPCServer.get_headers(stream, "x-custom-header")
        @test length(custom_values) == 2
        @test "value1" in custom_values
        @test "value2" in custom_values

        # Empty result for nonexistent header
        @test gRPCServer.get_headers(stream, "nonexistent") == String[]
    end

    @testset "gRPC Header Helpers" begin
        stream = gRPCServer.HTTP2Stream(1)
        stream.request_headers = [
            (":method", "POST"),
            (":path", "/helloworld.Greeter/SayHello"),
            (":authority", "localhost:50051"),
            ("content-type", "application/grpc+proto"),
            ("grpc-encoding", "gzip"),
            ("grpc-accept-encoding", "gzip,identity"),
            ("grpc-timeout", "10S"),
        ]

        @test gRPCServer.get_method(stream) == "POST"
        @test gRPCServer.get_path(stream) == "/helloworld.Greeter/SayHello"
        @test gRPCServer.get_authority(stream) == "localhost:50051"
        @test gRPCServer.get_content_type(stream) == "application/grpc+proto"
        @test gRPCServer.get_grpc_encoding(stream) == "gzip"
        @test gRPCServer.get_grpc_accept_encoding(stream) == "gzip,identity"
        @test gRPCServer.get_grpc_timeout(stream) == "10S"
    end

    @testset "get_metadata" begin
        stream = gRPCServer.HTTP2Stream(1)
        stream.request_headers = [
            (":method", "POST"),
            (":path", "/test"),
            ("content-type", "application/grpc"),
            ("te", "trailers"),
            ("grpc-encoding", "identity"),
            ("grpc-accept-encoding", "gzip"),
            ("grpc-timeout", "5S"),
            ("grpc-status", "0"),
            ("grpc-message", "OK"),
            ("x-request-id", "12345"),
            ("authorization", "Bearer token"),
            ("x-custom-bin", "binary-data"),
        ]

        metadata = gRPCServer.get_metadata(stream)

        # Should only include custom metadata
        @test length(metadata) == 3
        metadata_dict = Dict(metadata)
        @test haskey(metadata_dict, "x-request-id")
        @test metadata_dict["x-request-id"] == "12345"
        @test haskey(metadata_dict, "authorization")
        @test haskey(metadata_dict, "x-custom-bin")

        # Should NOT include pseudo-headers or reserved headers
        @test !haskey(metadata_dict, ":method")
        @test !haskey(metadata_dict, "content-type")
        @test !haskey(metadata_dict, "te")
        @test !haskey(metadata_dict, "grpc-encoding")
    end

    @testset "HTTP2Stream show" begin
        stream = gRPCServer.HTTP2Stream(1)
        str = sprint(show, stream)
        @test occursin("HTTP2Stream", str)
        @test occursin("id=1", str)
        @test occursin("state=IDLE", str)
        @test occursin("send_window=", str)
        @test occursin("recv_window=", str)

        # With RESET flag
        stream2 = gRPCServer.HTTP2Stream(3)
        stream2.reset = true
        str2 = sprint(show, stream2)
        @test occursin("RESET", str2)
    end

    @testset "Reset Stream Behavior" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)
        stream.reset = true

        # Reset stream cannot send or receive
        @test gRPCServer.can_send(stream) == false
        @test gRPCServer.can_receive(stream) == false
        @test gRPCServer.is_closed(stream) == true
    end

    @testset "End Stream Flag Behavior" begin
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)

        # Set end_stream_sent manually
        stream.end_stream_sent = true
        @test gRPCServer.can_send(stream) == false

        # Reset and test end_stream_received
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_headers!(stream2, false)
        stream2.end_stream_received = true
        @test gRPCServer.can_receive(stream2) == false
    end
end
