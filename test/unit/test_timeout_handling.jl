# AC7: Timeout Handling Tests
# Tests per gRPC HTTP/2 Protocol Specification

using Test
using Dates
using gRPCServer

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "AC7: Timeout Handling" begin

    # =========================================================================
    # T042: grpc-timeout Header Parsing
    # =========================================================================

    @testset "T042: grpc-timeout header parsing" begin

        @testset "Parse hours (H)" begin
            deadline = gRPCServer.parse_grpc_timeout("1H")
            @test deadline !== nothing
            # Should be approximately 1 hour from now
            diff_ms = Dates.value(deadline - now())
            @test diff_ms >= 3599000  # At least 59:59
            @test diff_ms <= 3601000  # At most 1:00:01
        end

        @testset "Parse minutes (M)" begin
            deadline = gRPCServer.parse_grpc_timeout("30M")
            @test deadline !== nothing
            diff_ms = Dates.value(deadline - now())
            @test diff_ms >= 1799000  # ~30 minutes
            @test diff_ms <= 1801000
        end

        @testset "Parse seconds (S)" begin
            deadline = gRPCServer.parse_grpc_timeout("60S")
            @test deadline !== nothing
            diff_ms = Dates.value(deadline - now())
            @test diff_ms >= 59000
            @test diff_ms <= 61000
        end

        @testset "Parse milliseconds (m)" begin
            deadline = gRPCServer.parse_grpc_timeout("500m")
            @test deadline !== nothing
            diff_ms = Dates.value(deadline - now())
            @test diff_ms >= 490
            @test diff_ms <= 510
        end

        @testset "Parse microseconds (u)" begin
            deadline = gRPCServer.parse_grpc_timeout("1000u")
            @test deadline !== nothing
            # 1000us = 1ms
            diff_ms = Dates.value(deadline - now())
            @test diff_ms >= 0
            @test diff_ms <= 10
        end

        @testset "Parse nanoseconds (n)" begin
            deadline = gRPCServer.parse_grpc_timeout("1000000n")
            @test deadline !== nothing
            # 1000000ns = 1ms
            diff_ms = Dates.value(deadline - now())
            @test diff_ms >= 0
            @test diff_ms <= 10
        end

        @testset "Parse zero timeout" begin
            deadline = gRPCServer.parse_grpc_timeout("0S")
            @test deadline !== nothing
        end

    end  # T042

    # =========================================================================
    # T043: Invalid Timeout Values
    # =========================================================================

    @testset "T043: Invalid timeout values" begin

        @testset "Empty string returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("") === nothing
        end

        @testset "Missing unit returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("100") === nothing
        end

        @testset "Missing value returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("S") === nothing
        end

        @testset "Negative value returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("-1S") === nothing
        end

        @testset "Invalid unit returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("1X") === nothing
            @test gRPCServer.parse_grpc_timeout("1s") === nothing  # lowercase
            @test gRPCServer.parse_grpc_timeout("1h") === nothing  # lowercase
        end

        @testset "Non-numeric value returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("abcS") === nothing
        end

        @testset "Float value returns nothing" begin
            @test gRPCServer.parse_grpc_timeout("1.5S") === nothing
        end

        @testset "All invalid test cases" begin
            for (input, _, should_fail) in ConformanceData.TIMEOUT_TEST_CASES
                if should_fail
                    result = gRPCServer.parse_grpc_timeout(input)
                    @test result === nothing
                end
            end
        end

    end  # T043

    # =========================================================================
    # T044: Timeout Format (output)
    # =========================================================================

    @testset "T044: Timeout format output" begin

        @testset "Format hours" begin
            deadline = now() + Hour(2)
            formatted = gRPCServer.format_grpc_timeout(deadline)
            @test endswith(formatted, "H")
            value = parse(Int, formatted[1:end-1])
            @test value >= 1 && value <= 2
        end

        @testset "Format minutes" begin
            deadline = now() + Minute(30)
            formatted = gRPCServer.format_grpc_timeout(deadline)
            @test endswith(formatted, "M")
            value = parse(Int, formatted[1:end-1])
            @test value >= 29 && value <= 30
        end

        @testset "Format seconds" begin
            deadline = now() + Second(45)
            formatted = gRPCServer.format_grpc_timeout(deadline)
            @test endswith(formatted, "S")
            value = parse(Int, formatted[1:end-1])
            @test value >= 44 && value <= 45
        end

        @testset "Format milliseconds" begin
            deadline = now() + Millisecond(500)
            formatted = gRPCServer.format_grpc_timeout(deadline)
            @test endswith(formatted, "m")
            value = parse(Int, formatted[1:end-1])
            @test value >= 490 && value <= 510
        end

        @testset "Format past deadline" begin
            deadline = now() - Second(1)
            formatted = gRPCServer.format_grpc_timeout(deadline)
            # Should format as 0 (past deadline)
            @test formatted == "0m"
        end

    end  # T044

    # =========================================================================
    # T045: ServerContext Deadline
    # =========================================================================

    @testset "T045: ServerContext deadline" begin

        @testset "Context with no deadline" begin
            ctx = gRPCServer.ServerContext()
            @test ctx.deadline === nothing
            @test gRPCServer.remaining_time(ctx) === nothing
        end

        @testset "Context with future deadline" begin
            future = now() + Second(60)
            ctx = gRPCServer.ServerContext(deadline=future)
            remaining = gRPCServer.remaining_time(ctx)
            @test remaining !== nothing
            @test remaining > 0
            @test remaining <= 60.5
        end

        @testset "Context with past deadline" begin
            past = now() - Second(5)
            ctx = gRPCServer.ServerContext(deadline=past)
            remaining = gRPCServer.remaining_time(ctx)
            @test remaining !== nothing
            @test remaining < 0
        end

        @testset "Context created from headers with timeout" begin
            headers = [
                (":method", "POST"),
                (":path", "/test/Method"),
                (":scheme", "http"),
                (":authority", "localhost"),
                ("content-type", "application/grpc"),
                ("grpc-timeout", "30S"),
            ]
            peer = gRPCServer.PeerInfo(Sockets.IPv4("127.0.0.1"), 12345)
            ctx = gRPCServer.create_context_from_headers(headers, peer)

            @test ctx.deadline !== nothing
            remaining = gRPCServer.remaining_time(ctx)
            @test remaining !== nothing
            @test remaining > 0
            @test remaining <= 31.0
        end

    end  # T045

    # =========================================================================
    # T046: Context Cancellation
    # =========================================================================

    @testset "T046: Context cancellation" begin

        @testset "Context starts not cancelled" begin
            ctx = gRPCServer.ServerContext()
            @test !gRPCServer.is_cancelled(ctx)
        end

        @testset "Context can be cancelled" begin
            ctx = gRPCServer.ServerContext()
            gRPCServer.cancel!(ctx)
            @test gRPCServer.is_cancelled(ctx)
        end

        @testset "Cancellation is persistent" begin
            ctx = gRPCServer.ServerContext()
            @test !gRPCServer.is_cancelled(ctx)
            gRPCServer.cancel!(ctx)
            @test gRPCServer.is_cancelled(ctx)
            @test gRPCServer.is_cancelled(ctx)  # Still cancelled
        end

    end  # T046

end  # AC7: Timeout Handling
