# gRPC Protocol Conformance Tests
# Reference: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

using Test
using gRPCServer
using Base64

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "gRPC Protocol Conformance" begin

    # =========================================================================
    # AC1: Request Validation Tests
    # =========================================================================

    @testset "AC1: Request Validation" begin

        @testset "Method validation - POST required" begin
            # Spec: Request → Request-Headers *Length-Prefixed-Message EOS
            # The :method pseudo-header MUST be POST

            # Valid: POST method
            request = TestUtils.MockHTTP2Request(method="POST")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test valid
            @test msg == ""

            # Invalid: Non-POST methods
            for invalid_method in ConformanceData.INVALID_METHODS
                request = TestUtils.MockHTTP2Request(method=invalid_method)
                headers = TestUtils.create_mock_headers(request)
                valid, msg = TestUtils.validate_grpc_request_headers(headers)
                @test !valid
                @test occursin("POST", msg)
            end
        end

        @testset "Content-type validation - application/grpc required" begin
            # Spec: content-type → "application/grpc" ["+proto" / "+json" / {custom}]

            # Valid content-types
            for (ct, is_valid, _) in ConformanceData.CONTENT_TYPE_TEST_CASES
                if is_valid
                    request = TestUtils.MockHTTP2Request(content_type=ct)
                    headers = TestUtils.create_mock_headers(request)
                    valid, _ = TestUtils.validate_grpc_request_headers(headers)
                    @test valid
                end
            end

            # Invalid content-types
            for (ct, is_valid, _) in ConformanceData.CONTENT_TYPE_TEST_CASES
                if !is_valid && ct != ""
                    request = TestUtils.MockHTTP2Request(content_type=ct)
                    headers = TestUtils.create_mock_headers(request)
                    valid, msg = TestUtils.validate_grpc_request_headers(headers)
                    @test !valid
                    @test occursin("content-type", lowercase(msg))
                end
            end

            # Missing content-type
            request = TestUtils.MockHTTP2Request(content_type=nothing)
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
            @test occursin("content-type", lowercase(msg))
        end

        @testset "Path format validation - /{service}/{method}" begin
            # Spec: :path → "/" Service-Name "/" {method name}

            # Valid paths
            for path in ConformanceData.VALID_PATHS
                request = TestUtils.MockHTTP2Request(path=path)
                headers = TestUtils.create_mock_headers(request)
                valid, _ = TestUtils.validate_grpc_request_headers(headers)
                @test valid
            end

            # Invalid paths
            for path in ConformanceData.INVALID_PATHS
                request = TestUtils.MockHTTP2Request(path=path)
                headers = TestUtils.create_mock_headers(request)
                valid, msg = TestUtils.validate_grpc_request_headers(headers)
                @test !valid
            end
        end

        @testset "TE header - trailers (warning if missing)" begin
            # Spec: te → "trailers" # Used to detect incompatible proxies

            # Valid: TE: trailers present
            request = TestUtils.MockHTTP2Request(te="trailers")
            stream = TestUtils.create_mock_stream(request)
            te_header = gRPCServer.get_header(stream, "te")
            @test te_header == "trailers"

            # Missing TE header should be handled (warning, not rejection)
            request_no_te = TestUtils.MockHTTP2Request(te=nothing)
            stream_no_te = TestUtils.create_mock_stream(request_no_te)
            te_header_missing = gRPCServer.get_header(stream_no_te, "te")
            @test te_header_missing === nothing
            # Server should still accept request (warning only per research.md)
        end

    end  # AC1

    # =========================================================================
    # AC2: Response Format Tests
    # =========================================================================

    @testset "AC2: Response Format" begin

        @testset "HTTP status must be 200" begin
            # Spec: Response → Response-Headers *Length-Prefixed-Message Trailers
            # All gRPC responses MUST use HTTP status 200

            valid, _ = TestUtils.validate_grpc_response(status=200, grpc_status=0)
            @test valid

            # Non-200 status is invalid for gRPC
            valid, msg = TestUtils.validate_grpc_response(status=400, grpc_status=3)
            @test !valid
            @test occursin("200", msg)
        end

        @testset "Response content-type must be application/grpc" begin
            # Response should mirror request content-type or use default

            valid, _ = TestUtils.validate_grpc_response(
                status=200,
                content_type="application/grpc",
                grpc_status=0
            )
            @test valid

            valid, _ = TestUtils.validate_grpc_response(
                status=200,
                content_type="application/grpc+proto",
                grpc_status=0
            )
            @test valid

            # Invalid response content-type
            valid, msg = TestUtils.validate_grpc_response(
                status=200,
                content_type="application/json",
                grpc_status=0
            )
            @test !valid
        end

        @testset "Trailers must include grpc-status" begin
            # Spec: Trailers → grpc-status [grpc-message] [grpc-status-details-bin] *Custom-Metadata

            # Valid: grpc-status present
            valid, _ = TestUtils.validate_grpc_response(status=200, grpc_status=0)
            @test valid

            # All valid status codes
            for code in 0:16
                valid, _ = TestUtils.validate_grpc_response(status=200, grpc_status=code)
                @test valid
            end

            # Invalid status codes
            valid, msg = TestUtils.validate_grpc_response(status=200, grpc_status=17)
            @test !valid
            @test occursin("grpc-status", msg)
        end

        @testset "Trailers-only response for errors" begin
            # Spec: In the case of an error, the body may be absent entirely
            # "Trailers-Only" response format is valid for immediate errors

            # Test that headers + trailers combined is valid (trailers-only format)
            # This is validated by checking grpc-status is in headers for trailers-only
            collector = TestUtils.MockResponseCollector()
            TestUtils.parse_response_headers!(collector, [
                (":status", "200"),
                ("content-type", "application/grpc"),
                ("grpc-status", "3"),
                ("grpc-message", "Invalid argument"),
            ])
            @test collector.http_status == 200
            @test collector.grpc_status == 3
            @test collector.grpc_message == "Invalid argument"
        end

    end  # AC2

    # =========================================================================
    # AC3: Message Encoding Tests
    # =========================================================================

    @testset "AC3: Message Encoding" begin

        @testset "Compressed flag encoding" begin
            # Spec: Compressed-Flag → 0 / 1 # 0 for uncompressed, 1 for compressed

            # Test uncompressed message
            msg = TestUtils.build_grpc_message(UInt8[0x01, 0x02, 0x03])
            @test msg[1] == 0x00  # Not compressed

            # Test compressed flag
            msg_compressed = TestUtils.build_grpc_message(UInt8[0x01, 0x02, 0x03]; compressed=true)
            @test msg_compressed[1] == 0x01  # Compressed
        end

        @testset "Message length big-endian encoding" begin
            # Spec: Message-Length → {4 bytes} # big-endian

            # Test with known length
            data = UInt8[0x01, 0x02, 0x03, 0x04, 0x05]  # 5 bytes
            msg = TestUtils.build_grpc_message(data)

            # Length should be in bytes 2-5 (big-endian)
            @test msg[2] == 0x00
            @test msg[3] == 0x00
            @test msg[4] == 0x00
            @test msg[5] == 0x05

            # Verify data follows
            @test msg[6:10] == data
        end

        @testset "Parse gRPC message" begin
            # Test round-trip
            original_data = UInt8[0xAA, 0xBB, 0xCC, 0xDD]
            encoded = TestUtils.build_grpc_message(original_data)
            compressed, decoded = TestUtils.parse_grpc_message(encoded)

            @test !compressed
            @test decoded == original_data
        end

        @testset "Message frame test cases" begin
            for (input, expected_compressed, expected_len, expected_msg, should_fail) in ConformanceData.MESSAGE_FRAME_TEST_CASES
                if should_fail
                    @test_throws Exception TestUtils.parse_grpc_message(input)
                else
                    compressed, message = TestUtils.parse_grpc_message(input)
                    @test compressed == (expected_compressed != 0x00)
                    @test length(message) == expected_len
                    @test message == expected_msg
                end
            end
        end

    end  # AC3

    # =========================================================================
    # AC4: Custom Metadata Tests
    # =========================================================================

    @testset "AC4: Custom Metadata" begin

        @testset "Binary metadata base64 decode" begin
            # Spec: Binary headers end with "-bin" suffix and are base64 encoded

            for (header_name, raw_value, is_binary, expected) in ConformanceData.BINARY_METADATA_TEST_CASES
                if is_binary
                    decoded = Base64.base64decode(raw_value)
                    @test decoded == expected
                end
            end
        end

        @testset "ASCII metadata preservation" begin
            # ASCII headers should be preserved as-is

            request = TestUtils.MockHTTP2Request(
                metadata=Dict(
                    "x-custom-header" => "custom-value",
                    "authorization" => "Bearer token123"
                )
            )
            stream = TestUtils.create_mock_stream(request)
            metadata = gRPCServer.get_metadata(stream)

            # Find custom headers
            has_custom = false
            has_auth = false
            for (name, value) in metadata
                if name == "x-custom-header"
                    @test value == "custom-value"
                    has_custom = true
                elseif name == "authorization"
                    @test value == "Bearer token123"
                    has_auth = true
                end
            end
            @test has_custom
            @test has_auth
        end

        @testset "Duplicate header order preservation" begin
            # Multiple headers with same name should preserve order

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
            @test values[1] == "value1"
            @test values[2] == "value2"
            @test values[3] == "value3"
        end

    end  # AC4

    # =========================================================================
    # AC5: Error Mapping Tests (Placeholder - detailed tests in test_errors.jl)
    # =========================================================================

    @testset "AC5: Error Mapping (basic)" begin

        @testset "gRPC status codes are defined" begin
            # Verify all 17 status codes are defined
            @test Int(StatusCode.OK) == 0
            @test Int(StatusCode.CANCELLED) == 1
            @test Int(StatusCode.UNKNOWN) == 2
            @test Int(StatusCode.INVALID_ARGUMENT) == 3
            @test Int(StatusCode.DEADLINE_EXCEEDED) == 4
            @test Int(StatusCode.NOT_FOUND) == 5
            @test Int(StatusCode.ALREADY_EXISTS) == 6
            @test Int(StatusCode.PERMISSION_DENIED) == 7
            @test Int(StatusCode.RESOURCE_EXHAUSTED) == 8
            @test Int(StatusCode.FAILED_PRECONDITION) == 9
            @test Int(StatusCode.ABORTED) == 10
            @test Int(StatusCode.OUT_OF_RANGE) == 11
            @test Int(StatusCode.UNIMPLEMENTED) == 12
            @test Int(StatusCode.INTERNAL) == 13
            @test Int(StatusCode.UNAVAILABLE) == 14
            @test Int(StatusCode.DATA_LOSS) == 15
            @test Int(StatusCode.UNAUTHENTICATED) == 16
        end

    end  # AC5

    # =========================================================================
    # AC6: Connection Management (Placeholder - detailed tests in test_http2_conformance.jl)
    # =========================================================================

    @testset "AC6: Connection Management (basic)" begin

        @testset "Connection preface constant" begin
            @test gRPCServer.CONNECTION_PREFACE == b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
        end

    end  # AC6

    # =========================================================================
    # AC7: Timeout Handling (Placeholder - detailed tests in test_context.jl)
    # =========================================================================

    @testset "AC7: Timeout Handling (basic)" begin

        @testset "Timeout parsing" begin
            # Basic timeout parsing test
            deadline = gRPCServer.parse_grpc_timeout("30S")
            @test deadline !== nothing

            # Invalid timeout
            deadline_invalid = gRPCServer.parse_grpc_timeout("")
            @test deadline_invalid === nothing
        end

    end  # AC7

end  # gRPC Protocol Conformance
