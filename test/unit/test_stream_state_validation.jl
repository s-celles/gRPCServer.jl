# Unit tests for stream state validation in gRPC responses
# These tests verify the fix for GitHub Issue #6

using Test
using gRPCServer

@testset "Stream State Validation Tests" begin
    @testset "can_send function behavior" begin
        # Test that can_send returns true for OPEN state
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)
        @test stream.state == gRPCServer.StreamState.OPEN
        @test gRPCServer.can_send(stream) == true

        # Test that can_send returns true for HALF_CLOSED_REMOTE state
        stream2 = gRPCServer.HTTP2Stream(3)
        gRPCServer.receive_headers!(stream2, true)
        @test stream2.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        @test gRPCServer.can_send(stream2) == true

        # Test that can_send returns false for CLOSED state
        stream3 = gRPCServer.HTTP2Stream(5)
        gRPCServer.receive_headers!(stream3, true)
        gRPCServer.send_headers!(stream3, true)
        @test stream3.state == gRPCServer.StreamState.CLOSED
        @test gRPCServer.can_send(stream3) == false

        # Test that can_send returns false for reset stream
        stream4 = gRPCServer.HTTP2Stream(7)
        gRPCServer.receive_headers!(stream4, false)
        gRPCServer.receive_rst_stream!(stream4, UInt32(8))  # CANCEL
        @test gRPCServer.can_send(stream4) == false

        # Test that can_send returns false for IDLE state
        stream5 = gRPCServer.HTTP2Stream(9)
        @test stream5.state == gRPCServer.StreamState.IDLE
        @test gRPCServer.can_send(stream5) == false

        # Test that can_send returns false after end_stream_sent
        stream6 = gRPCServer.HTTP2Stream(11)
        gRPCServer.receive_headers!(stream6, false)
        stream6.end_stream_sent = true
        @test gRPCServer.can_send(stream6) == false
    end

    @testset "can_send_on_stream helper function" begin
        # Create a connection with a stream
        conn = gRPCServer.HTTP2Connection()
        conn.state = gRPCServer.ConnectionState.OPEN

        # Test with non-existent stream
        @test gRPCServer.can_send_on_stream(conn, UInt32(999)) == false

        # Create a stream in OPEN state
        stream = gRPCServer.create_stream(conn, UInt32(1))
        gRPCServer.receive_headers!(stream, false)
        @test gRPCServer.can_send_on_stream(conn, UInt32(1)) == true

        # Create a stream in HALF_CLOSED_REMOTE state (typical for unary RPC)
        stream2 = gRPCServer.create_stream(conn, UInt32(3))
        gRPCServer.receive_headers!(stream2, true)
        @test gRPCServer.can_send_on_stream(conn, UInt32(3)) == true

        # Create a stream and close it
        stream3 = gRPCServer.create_stream(conn, UInt32(5))
        gRPCServer.receive_headers!(stream3, true)
        gRPCServer.send_headers!(stream3, true)
        @test gRPCServer.can_send_on_stream(conn, UInt32(5)) == false
    end

    @testset "StreamError export" begin
        # Verify StreamError is accessible and can be constructed
        err = gRPCServer.StreamError(UInt32(1), UInt32(2), "Test error")
        @test err isa Exception
        @test err.stream_id == 1
        @test err.error_code == 2
        @test err.message == "Test error"
    end

    @testset "RST_STREAM marks stream as not sendable" begin
        # When client sends RST_STREAM, stream should no longer be sendable
        stream = gRPCServer.HTTP2Stream(1)
        gRPCServer.receive_headers!(stream, false)
        @test gRPCServer.can_send(stream) == true

        # Receive RST_STREAM from client
        gRPCServer.receive_rst_stream!(stream, UInt32(8))  # CANCEL

        # Stream should now be not sendable
        @test gRPCServer.can_send(stream) == false
        @test stream.reset == true
        @test stream.state == gRPCServer.StreamState.CLOSED
    end

    @testset "Stream state after receiving END_STREAM with DATA" begin
        # Simulate a unary RPC where client sends request with END_STREAM
        stream = gRPCServer.HTTP2Stream(1)

        # Client sends HEADERS (no END_STREAM yet)
        gRPCServer.receive_headers!(stream, false)
        @test stream.state == gRPCServer.StreamState.OPEN
        @test gRPCServer.can_send(stream) == true

        # Client sends DATA with END_STREAM
        gRPCServer.receive_data!(stream, UInt8[1, 2, 3, 4, 5], true)
        @test stream.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        @test gRPCServer.can_send(stream) == true  # Server can still send response

        # Server sends response headers (no END_STREAM)
        gRPCServer.send_headers!(stream, false)
        @test stream.state == gRPCServer.StreamState.HALF_CLOSED_REMOTE
        @test gRPCServer.can_send(stream) == true

        # Server sends trailers with END_STREAM
        gRPCServer.send_headers!(stream, true)
        @test stream.state == gRPCServer.StreamState.CLOSED
        @test gRPCServer.can_send(stream) == false
    end
end
