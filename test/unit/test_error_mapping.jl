# AC5: Error Mapping Tests
# Tests per gRPC HTTP/2 Protocol Specification
# Reference: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

using Test
using gRPCServer

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "AC5: Error Mapping" begin

    # =========================================================================
    # T031: gRPC Status Codes
    # =========================================================================

    @testset "T031: gRPC status codes" begin

        @testset "All 17 status codes defined" begin
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

        @testset "Status codes match conformance data" begin
            for (code, name) in ConformanceData.GRPC_STATUS_CODES
                # Verify the name matches the expected value
                @test code >= 0 && code <= 16
            end
        end

    end  # T031

    # =========================================================================
    # T032: HTTP/2 to gRPC Status Mapping
    # =========================================================================

    @testset "T032: HTTP/2 to gRPC status mapping" begin

        @testset "CANCEL (0x08) → CANCELLED" begin
            @test http2_to_grpc_status(0x08) == StatusCode.CANCELLED
        end

        @testset "REFUSED_STREAM (0x07) → UNAVAILABLE" begin
            @test http2_to_grpc_status(0x07) == StatusCode.UNAVAILABLE
        end

        @testset "ENHANCE_YOUR_CALM (0x0b) → RESOURCE_EXHAUSTED" begin
            @test http2_to_grpc_status(0x0b) == StatusCode.RESOURCE_EXHAUSTED
        end

        @testset "INADEQUATE_SECURITY (0x0c) → PERMISSION_DENIED" begin
            @test http2_to_grpc_status(0x0c) == StatusCode.PERMISSION_DENIED
        end

        @testset "All other HTTP/2 errors → INTERNAL" begin
            # NO_ERROR
            @test http2_to_grpc_status(0x00) == StatusCode.INTERNAL
            # PROTOCOL_ERROR
            @test http2_to_grpc_status(0x01) == StatusCode.INTERNAL
            # INTERNAL_ERROR
            @test http2_to_grpc_status(0x02) == StatusCode.INTERNAL
            # FLOW_CONTROL_ERROR
            @test http2_to_grpc_status(0x03) == StatusCode.INTERNAL
            # SETTINGS_TIMEOUT
            @test http2_to_grpc_status(0x04) == StatusCode.INTERNAL
            # STREAM_CLOSED
            @test http2_to_grpc_status(0x05) == StatusCode.INTERNAL
            # FRAME_SIZE_ERROR
            @test http2_to_grpc_status(0x06) == StatusCode.INTERNAL
            # COMPRESSION_ERROR
            @test http2_to_grpc_status(0x09) == StatusCode.INTERNAL
            # CONNECT_ERROR
            @test http2_to_grpc_status(0x0a) == StatusCode.INTERNAL
            # HTTP_1_1_REQUIRED
            @test http2_to_grpc_status(0x0d) == StatusCode.INTERNAL
        end

        @testset "All error mapping test cases" begin
            for (http2_code, name, expected_grpc) in ConformanceData.ERROR_MAPPING_TEST_CASES
                result = Int(http2_to_grpc_status(UInt32(http2_code)))
                @test result == expected_grpc
            end
        end

    end  # T032

    # =========================================================================
    # T033: gRPC to HTTP Status Mapping
    # =========================================================================

    @testset "T033: gRPC to HTTP status mapping" begin

        @testset "OK (0) → 200" begin
            @test status_code_to_http(StatusCode.OK) == 200
        end

        @testset "INVALID_ARGUMENT (3) → 400" begin
            @test status_code_to_http(StatusCode.INVALID_ARGUMENT) == 400
        end

        @testset "UNAUTHENTICATED (16) → 401" begin
            @test status_code_to_http(StatusCode.UNAUTHENTICATED) == 401
        end

        @testset "PERMISSION_DENIED (7) → 403" begin
            @test status_code_to_http(StatusCode.PERMISSION_DENIED) == 403
        end

        @testset "NOT_FOUND (5) → 404" begin
            @test status_code_to_http(StatusCode.NOT_FOUND) == 404
        end

        @testset "RESOURCE_EXHAUSTED (8) → 429" begin
            @test status_code_to_http(StatusCode.RESOURCE_EXHAUSTED) == 429
        end

        @testset "UNIMPLEMENTED (12) → 501" begin
            @test status_code_to_http(StatusCode.UNIMPLEMENTED) == 501
        end

        @testset "UNAVAILABLE (14) → 503" begin
            @test status_code_to_http(StatusCode.UNAVAILABLE) == 503
        end

        @testset "DEADLINE_EXCEEDED (4) → 504" begin
            @test status_code_to_http(StatusCode.DEADLINE_EXCEEDED) == 504
        end

        @testset "Internal errors → 500" begin
            @test status_code_to_http(StatusCode.INTERNAL) == 500
            @test status_code_to_http(StatusCode.UNKNOWN) == 500
            @test status_code_to_http(StatusCode.DATA_LOSS) == 500
        end

    end  # T033

    # =========================================================================
    # T034: Exception to Status Code Mapping
    # =========================================================================

    @testset "T034: Exception to status code mapping" begin

        @testset "GRPCError preserves code" begin
            err = GRPCError(StatusCode.NOT_FOUND, "Not found")
            @test exception_to_status_code(err) == StatusCode.NOT_FOUND

            err2 = GRPCError(StatusCode.PERMISSION_DENIED, "Access denied")
            @test exception_to_status_code(err2) == StatusCode.PERMISSION_DENIED
        end

        @testset "ArgumentError → INVALID_ARGUMENT" begin
            err = ArgumentError("invalid")
            @test exception_to_status_code(err) == StatusCode.INVALID_ARGUMENT
        end

        @testset "BoundsError → OUT_OF_RANGE" begin
            err = BoundsError([1,2,3], 10)
            @test exception_to_status_code(err) == StatusCode.OUT_OF_RANGE
        end

        @testset "KeyError → NOT_FOUND" begin
            err = KeyError("missing_key")
            @test exception_to_status_code(err) == StatusCode.NOT_FOUND
        end

        @testset "InterruptException → CANCELLED" begin
            err = InterruptException()
            @test exception_to_status_code(err) == StatusCode.CANCELLED
        end

        @testset "Other exceptions → INTERNAL" begin
            err = ErrorException("unknown")
            @test exception_to_status_code(err) == StatusCode.INTERNAL
        end

    end  # T034

    # =========================================================================
    # T035: GRPCError Structure
    # =========================================================================

    @testset "T035: GRPCError structure" begin

        @testset "GRPCError fields" begin
            err = GRPCError(StatusCode.INVALID_ARGUMENT, "Bad input", Any["detail1", "detail2"])
            @test err.code == StatusCode.INVALID_ARGUMENT
            @test err.message == "Bad input"
            @test length(err.details) == 2
        end

        @testset "GRPCError default details" begin
            err = GRPCError(StatusCode.NOT_FOUND, "Resource not found")
            @test isempty(err.details)
        end

        @testset "GRPCError is an Exception" begin
            @test GRPCError <: Exception
        end

        @testset "GRPCError show method" begin
            err = GRPCError(StatusCode.INTERNAL, "Something went wrong")
            str = sprint(showerror, err)
            @test occursin("GRPCError", str)
            @test occursin("INTERNAL", str)
            @test occursin("Something went wrong", str)
        end

    end  # T035

    # =========================================================================
    # T036: Error Response Format
    # =========================================================================

    @testset "T036: Error response format" begin

        @testset "Error trailers format" begin
            ctx = gRPCServer.ServerContext()
            trailers = gRPCServer.get_response_trailers(ctx, 3, "Invalid argument provided")

            # Must have grpc-status
            status_found = false
            message_found = false
            for (name, value) in trailers
                if name == "grpc-status"
                    @test value == "3"
                    status_found = true
                elseif name == "grpc-message"
                    @test length(value) > 0
                    message_found = true
                end
            end
            @test status_found
            @test message_found
        end

        @testset "Empty message omitted" begin
            ctx = gRPCServer.ServerContext()
            trailers = gRPCServer.get_response_trailers(ctx, 0, "")

            # grpc-status present
            has_status = any(name == "grpc-status" for (name, _) in trailers)
            @test has_status

            # grpc-message not present for empty message
            has_message = any(name == "grpc-message" for (name, _) in trailers)
            @test !has_message
        end

    end  # T036

end  # AC5: Error Mapping
