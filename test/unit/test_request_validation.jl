# AC1: Request Validation Tests
# Tests per gRPC HTTP/2 Protocol Specification
# Reference: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

using Test
using gRPCServer

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "AC1: Request Validation" begin

    # =========================================================================
    # T008: Method Validation - POST required
    # =========================================================================

    @testset "T008: Method validation" begin

        @testset "Valid: POST method accepted" begin
            request = TestUtils.MockHTTP2Request(method="POST")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test valid
            @test msg == ""
        end

        @testset "Invalid: GET method rejected" begin
            request = TestUtils.MockHTTP2Request(method="GET")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
            @test occursin("POST", msg)
        end

        @testset "Invalid: PUT method rejected" begin
            request = TestUtils.MockHTTP2Request(method="PUT")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "Invalid: DELETE method rejected" begin
            request = TestUtils.MockHTTP2Request(method="DELETE")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "Invalid: OPTIONS method rejected" begin
            request = TestUtils.MockHTTP2Request(method="OPTIONS")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "All invalid methods from test data" begin
            for method in ConformanceData.INVALID_METHODS
                request = TestUtils.MockHTTP2Request(method=method)
                headers = TestUtils.create_mock_headers(request)
                valid, _ = TestUtils.validate_grpc_request_headers(headers)
                @test !valid
            end
        end

    end  # T008

    # =========================================================================
    # T009: Content-Type Validation - application/grpc required
    # =========================================================================

    @testset "T009: Content-type validation" begin

        @testset "Valid: application/grpc" begin
            request = TestUtils.MockHTTP2Request(content_type="application/grpc")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Valid: application/grpc+proto" begin
            request = TestUtils.MockHTTP2Request(content_type="application/grpc+proto")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Valid: application/grpc+json" begin
            request = TestUtils.MockHTTP2Request(content_type="application/grpc+json")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Valid: application/grpc with charset parameter" begin
            request = TestUtils.MockHTTP2Request(content_type="application/grpc; charset=utf-8")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Invalid: application/json" begin
            request = TestUtils.MockHTTP2Request(content_type="application/json")
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
            @test occursin("content-type", lowercase(msg))
        end

        @testset "Invalid: text/plain" begin
            request = TestUtils.MockHTTP2Request(content_type="text/plain")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "Invalid: missing content-type" begin
            request = TestUtils.MockHTTP2Request(content_type=nothing)
            headers = TestUtils.create_mock_headers(request)
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
            @test occursin("content-type", lowercase(msg))
        end

        @testset "All content-type test cases" begin
            for (ct, is_valid, _) in ConformanceData.CONTENT_TYPE_TEST_CASES
                if ct == ""
                    continue  # Skip empty string (handled by missing test)
                end
                request = TestUtils.MockHTTP2Request(content_type=ct)
                headers = TestUtils.create_mock_headers(request)
                valid, _ = TestUtils.validate_grpc_request_headers(headers)
                @test valid == is_valid
            end
        end

    end  # T009

    # =========================================================================
    # T010: Path Format Validation - /{service}/{method}
    # =========================================================================

    @testset "T010: Path format validation" begin

        @testset "Valid: standard service path" begin
            request = TestUtils.MockHTTP2Request(path="/helloworld.Greeter/SayHello")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Valid: health check path" begin
            request = TestUtils.MockHTTP2Request(path="/grpc.health.v1.Health/Check")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Valid: minimal path" begin
            request = TestUtils.MockHTTP2Request(path="/a/b")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Invalid: empty path" begin
            request = TestUtils.MockHTTP2Request(path="")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "Invalid: root path only" begin
            request = TestUtils.MockHTTP2Request(path="/")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "Invalid: single segment" begin
            request = TestUtils.MockHTTP2Request(path="/service")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "Invalid: missing leading slash" begin
            request = TestUtils.MockHTTP2Request(path="service/method")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
        end

        @testset "All valid paths" begin
            for path in ConformanceData.VALID_PATHS
                request = TestUtils.MockHTTP2Request(path=path)
                headers = TestUtils.create_mock_headers(request)
                valid, _ = TestUtils.validate_grpc_request_headers(headers)
                @test valid
            end
        end

        @testset "All invalid paths" begin
            for path in ConformanceData.INVALID_PATHS
                request = TestUtils.MockHTTP2Request(path=path)
                headers = TestUtils.create_mock_headers(request)
                valid, _ = TestUtils.validate_grpc_request_headers(headers)
                @test !valid
            end
        end

    end  # T010

    # =========================================================================
    # T011: TE Header Validation (warning only, not rejection)
    # =========================================================================

    @testset "T011: TE header validation" begin

        @testset "Valid: TE trailers present" begin
            request = TestUtils.MockHTTP2Request(te="trailers")
            stream = TestUtils.create_mock_stream(request)
            te = gRPCServer.get_header(stream, "te")
            @test te == "trailers"
        end

        @testset "Request accepted: TE header missing (warning only)" begin
            request = TestUtils.MockHTTP2Request(te=nothing)
            headers = TestUtils.create_mock_headers(request)
            # Request should still be valid (warning only per spec interpretation)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Request accepted: wrong TE value (warning only)" begin
            request = TestUtils.MockHTTP2Request(te="chunked")
            headers = TestUtils.create_mock_headers(request)
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Stream exposes TE header correctly" begin
            for te_value in ["trailers", "chunked", "gzip"]
                request = TestUtils.MockHTTP2Request(te=te_value)
                stream = TestUtils.create_mock_stream(request)
                te = gRPCServer.get_header(stream, "te")
                @test te == te_value
            end
        end

    end  # T011

    # =========================================================================
    # T012: Timeout Header Parsing
    # =========================================================================

    @testset "T012: Timeout header parsing" begin

        @testset "Valid timeouts parse correctly" begin
            # 30 seconds
            deadline = gRPCServer.parse_grpc_timeout("30S")
            @test deadline !== nothing

            # 1 hour
            deadline = gRPCServer.parse_grpc_timeout("1H")
            @test deadline !== nothing

            # 500 milliseconds
            deadline = gRPCServer.parse_grpc_timeout("500m")
            @test deadline !== nothing

            # 5 minutes
            deadline = gRPCServer.parse_grpc_timeout("5M")
            @test deadline !== nothing
        end

        @testset "Invalid timeouts return nothing" begin
            @test gRPCServer.parse_grpc_timeout("") === nothing
            @test gRPCServer.parse_grpc_timeout("abc") === nothing
            @test gRPCServer.parse_grpc_timeout("1X") === nothing
            @test gRPCServer.parse_grpc_timeout("-1S") === nothing
        end

        @testset "All timeout test cases" begin
            for (input, _, should_fail) in ConformanceData.TIMEOUT_TEST_CASES
                result = gRPCServer.parse_grpc_timeout(input)
                if should_fail
                    @test result === nothing
                else
                    @test result !== nothing
                end
            end
        end

        @testset "Timeout creates deadline in future" begin
            deadline = gRPCServer.parse_grpc_timeout("60S")
            @test deadline !== nothing
            @test deadline > Dates.now()
        end

    end  # T012

    # =========================================================================
    # T013: Authority/Host Validation
    # =========================================================================

    @testset "T013: Authority validation" begin

        @testset "Authority header accessible" begin
            request = TestUtils.MockHTTP2Request(authority="localhost:50051")
            stream = TestUtils.create_mock_stream(request)
            authority = gRPCServer.get_authority(stream)
            @test authority == "localhost:50051"
        end

        @testset "Authority with different formats" begin
            for auth in ["localhost:50051", "127.0.0.1:8080", "example.com:443", "api.service.local"]
                request = TestUtils.MockHTTP2Request(authority=auth)
                stream = TestUtils.create_mock_stream(request)
                @test gRPCServer.get_authority(stream) == auth
            end
        end

    end  # T013

    # =========================================================================
    # T014: Required Pseudo-Headers
    # =========================================================================

    @testset "T014: Required pseudo-headers" begin

        @testset "All required pseudo-headers present" begin
            headers = [
                (":method", "POST"),
                (":path", "/test.Service/Method"),
                (":scheme", "http"),
                (":authority", "localhost:50051"),
                ("content-type", "application/grpc"),
            ]
            valid, _ = TestUtils.validate_grpc_request_headers(headers)
            @test valid
        end

        @testset "Stream helpers for pseudo-headers" begin
            request = TestUtils.MockHTTP2Request()
            stream = TestUtils.create_mock_stream(request)

            @test gRPCServer.get_method(stream) == "POST"
            @test gRPCServer.get_path(stream) == "/pkg.Service/Method"
            @test gRPCServer.get_authority(stream) == "localhost:50051"
        end

        @testset "Missing :path header fails validation" begin
            headers = [
                (":method", "POST"),
                (":scheme", "http"),
                (":authority", "localhost:50051"),
                ("content-type", "application/grpc"),
            ]
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
            @test occursin("path", lowercase(msg))
        end

        @testset "Missing :method header fails validation" begin
            headers = [
                (":path", "/test.Service/Method"),
                (":scheme", "http"),
                (":authority", "localhost:50051"),
                ("content-type", "application/grpc"),
            ]
            valid, msg = TestUtils.validate_grpc_request_headers(headers)
            @test !valid
            @test occursin("method", lowercase(msg))
        end

    end  # T014

end  # AC1: Request Validation
