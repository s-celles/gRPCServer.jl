# AC4: Custom Metadata Tests
# Tests per gRPC HTTP/2 Protocol Specification
# Reference: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

using Test
using Base64
using gRPCServer

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "AC4: Custom Metadata" begin

    # =========================================================================
    # T027: ASCII Metadata Headers
    # =========================================================================

    @testset "T027: ASCII metadata headers" begin

        @testset "Custom string metadata preserved" begin
            request = TestUtils.MockHTTP2Request(
                metadata=Dict(
                    "x-custom-header" => "custom-value",
                    "x-another" => "another-value"
                )
            )
            stream = TestUtils.create_mock_stream(request)
            metadata = gRPCServer.get_metadata(stream)

            found_custom = false
            found_another = false
            for (name, value) in metadata
                if name == "x-custom-header"
                    @test value == "custom-value"
                    found_custom = true
                elseif name == "x-another"
                    @test value == "another-value"
                    found_another = true
                end
            end
            @test found_custom
            @test found_another
        end

        @testset "Authorization header preserved" begin
            request = TestUtils.MockHTTP2Request(
                metadata=Dict("authorization" => "Bearer token123")
            )
            stream = TestUtils.create_mock_stream(request)
            metadata = gRPCServer.get_metadata(stream)

            found = false
            for (name, value) in metadata
                if name == "authorization"
                    @test value == "Bearer token123"
                    found = true
                end
            end
            @test found
        end

        @testset "Metadata case-insensitive lookup" begin
            request = TestUtils.MockHTTP2Request(
                metadata=Dict("X-Custom-Header" => "value")
            )
            stream = TestUtils.create_mock_stream(request)

            # Should find with any case
            @test gRPCServer.get_header(stream, "x-custom-header") == "value"
            @test gRPCServer.get_header(stream, "X-CUSTOM-HEADER") == "value"
        end

    end  # T027

    # =========================================================================
    # T028: Binary Metadata Headers (-bin suffix)
    # =========================================================================

    @testset "T028: Binary metadata headers" begin

        @testset "Binary header suffix convention" begin
            # Binary headers MUST end with "-bin"
            @test endswith("x-custom-bin", "-bin")
            @test !endswith("x-custom", "-bin")
        end

        @testset "Binary metadata base64 decoding" begin
            for (header_name, raw_value, is_binary, expected) in ConformanceData.BINARY_METADATA_TEST_CASES
                if is_binary
                    decoded = base64decode(raw_value)
                    @test decoded == expected
                end
            end
        end

        @testset "Context handles binary response headers" begin
            ctx = gRPCServer.ServerContext()
            binary_data = UInt8[0x01, 0x02, 0x03, 0x04]
            gRPCServer.set_header!(ctx, "x-trace-bin", binary_data)

            headers = gRPCServer.get_response_headers(ctx)
            for (name, value) in headers
                if name == "x-trace-bin"
                    # Should be base64 encoded
                    @test value isa String
                    @test base64decode(value) == binary_data
                end
            end
        end

        @testset "Context handles binary trailers" begin
            ctx = gRPCServer.ServerContext()
            binary_data = UInt8[0xDE, 0xAD, 0xBE, 0xEF]
            gRPCServer.set_trailer!(ctx, "x-result-bin", binary_data)

            trailers = gRPCServer.get_response_trailers(ctx, 0, "")
            for (name, value) in trailers
                if name == "x-result-bin"
                    @test value isa String
                    @test base64decode(value) == binary_data
                end
            end
        end

    end  # T028

    # =========================================================================
    # T029: Duplicate Headers
    # =========================================================================

    @testset "T029: Duplicate headers" begin

        @testset "Multiple headers with same name preserved" begin
            headers = [
                (":method", "POST"),
                (":path", "/test/Method"),
                (":scheme", "http"),
                (":authority", "localhost"),
                ("content-type", "application/grpc"),
                ("x-multi", "value1"),
                ("x-multi", "value2"),
                ("x-multi", "value3"),
            ]

            stream = gRPCServer.HTTP2Stream(UInt32(1))
            stream.request_headers = headers
            stream.headers_complete = true

            values = gRPCServer.get_headers(stream, "x-multi")
            @test length(values) == 3
        end

        @testset "Duplicate headers preserve order" begin
            headers = [
                (":method", "POST"),
                (":path", "/test/Method"),
                (":scheme", "http"),
                (":authority", "localhost"),
                ("content-type", "application/grpc"),
                ("x-ordered", "first"),
                ("x-ordered", "second"),
                ("x-ordered", "third"),
            ]

            stream = gRPCServer.HTTP2Stream(UInt32(1))
            stream.request_headers = headers
            stream.headers_complete = true

            values = gRPCServer.get_headers(stream, "x-ordered")
            @test values[1] == "first"
            @test values[2] == "second"
            @test values[3] == "third"
        end

        @testset "get_header returns first value" begin
            headers = [
                (":method", "POST"),
                (":path", "/test/Method"),
                (":scheme", "http"),
                (":authority", "localhost"),
                ("content-type", "application/grpc"),
                ("x-first", "value1"),
                ("x-first", "value2"),
            ]

            stream = gRPCServer.HTTP2Stream(UInt32(1))
            stream.request_headers = headers
            stream.headers_complete = true

            # get_header returns first occurrence
            @test gRPCServer.get_header(stream, "x-first") == "value1"
        end

    end  # T029

    # =========================================================================
    # T030: Reserved Headers Filtering
    # =========================================================================

    @testset "T030: Reserved headers filtering" begin

        @testset "Pseudo-headers excluded from metadata" begin
            request = TestUtils.MockHTTP2Request(
                metadata=Dict("x-custom" => "value")
            )
            stream = TestUtils.create_mock_stream(request)
            metadata = gRPCServer.get_metadata(stream)

            for (name, _) in metadata
                @test !startswith(name, ":")
            end
        end

        @testset "Reserved gRPC headers excluded from metadata" begin
            headers = [
                (":method", "POST"),
                (":path", "/test/Method"),
                (":scheme", "http"),
                (":authority", "localhost"),
                ("content-type", "application/grpc"),
                ("te", "trailers"),
                ("grpc-encoding", "gzip"),
                ("grpc-accept-encoding", "gzip,deflate"),
                ("grpc-timeout", "10S"),
                ("x-custom", "custom-value"),
            ]

            stream = gRPCServer.HTTP2Stream(UInt32(1))
            stream.request_headers = headers
            stream.headers_complete = true

            metadata = gRPCServer.get_metadata(stream)
            metadata_names = [name for (name, _) in metadata]

            # Reserved headers should not be in metadata
            @test "content-type" ∉ metadata_names
            @test "te" ∉ metadata_names
            @test "grpc-encoding" ∉ metadata_names
            @test "grpc-accept-encoding" ∉ metadata_names
            @test "grpc-timeout" ∉ metadata_names

            # Custom headers should be included
            @test "x-custom" ∈ metadata_names
        end

        @testset "Context metadata access" begin
            headers = [
                (":method", "POST"),
                (":path", "/test/Method"),
                (":scheme", "http"),
                (":authority", "localhost"),
                ("content-type", "application/grpc"),
                ("x-request-id", "abc123"),
                ("authorization", "Bearer token"),
            ]

            stream = gRPCServer.HTTP2Stream(UInt32(1))
            stream.request_headers = headers

            peer = gRPCServer.PeerInfo(Sockets.IPv4("127.0.0.1"), 12345)
            ctx = gRPCServer.create_context_from_headers(headers, peer)

            # Should be able to get custom metadata
            @test gRPCServer.get_metadata(ctx, "x-request-id") == "abc123"
            @test gRPCServer.get_metadata(ctx, "authorization") == "Bearer token"

            # Non-existent metadata returns nothing
            @test gRPCServer.get_metadata(ctx, "x-nonexistent") === nothing
        end

    end  # T030

end  # AC4: Custom Metadata
