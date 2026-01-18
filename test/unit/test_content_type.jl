# Unit tests for content-type response mirroring
# These tests verify the fix for GitHub Issue #6 (content-type handling)

using Test
using gRPCServer

@testset "Content-Type Response Tests" begin
    @testset "get_response_content_type helper function" begin
        # Test with application/grpc+proto request
        stream1 = gRPCServer.HTTP2Stream(1)
        stream1.request_headers = [
            (":method", "POST"),
            (":path", "/test.Service/Method"),
            ("content-type", "application/grpc+proto"),
        ]
        @test gRPCServer.get_response_content_type(stream1) == "application/grpc+proto"

        # Test with application/grpc request
        stream2 = gRPCServer.HTTP2Stream(3)
        stream2.request_headers = [
            (":method", "POST"),
            (":path", "/test.Service/Method"),
            ("content-type", "application/grpc"),
        ]
        @test gRPCServer.get_response_content_type(stream2) == "application/grpc"

        # Test with application/grpc+json request
        stream3 = gRPCServer.HTTP2Stream(5)
        stream3.request_headers = [
            (":method", "POST"),
            (":path", "/test.Service/Method"),
            ("content-type", "application/grpc+json"),
        ]
        @test gRPCServer.get_response_content_type(stream3) == "application/grpc+json"

        # Test with missing content-type (should default to application/grpc)
        stream4 = gRPCServer.HTTP2Stream(7)
        stream4.request_headers = [
            (":method", "POST"),
            (":path", "/test.Service/Method"),
        ]
        @test gRPCServer.get_response_content_type(stream4) == "application/grpc"

        # Test with non-grpc content-type (should default to application/grpc)
        stream5 = gRPCServer.HTTP2Stream(9)
        stream5.request_headers = [
            (":method", "POST"),
            (":path", "/test.Service/Method"),
            ("content-type", "text/plain"),
        ]
        @test gRPCServer.get_response_content_type(stream5) == "application/grpc"
    end

    @testset "Content-type case sensitivity" begin
        # Content-type header matching should be case-insensitive
        stream = gRPCServer.HTTP2Stream(1)
        stream.request_headers = [
            (":method", "POST"),
            ("Content-Type", "application/grpc+proto"),  # Different case
        ]
        content_type = gRPCServer.get_content_type(stream)
        @test content_type == "application/grpc+proto"
    end
end
