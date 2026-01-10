# Unit tests for error types and status codes

using Test
using gRPCServer

@testset "Error Types Unit Tests" begin
    @testset "StatusCode Enum" begin
        # All 17 gRPC status codes should exist
        @test StatusCode.OK isa StatusCode.T
        @test StatusCode.CANCELLED isa StatusCode.T
        @test StatusCode.UNKNOWN isa StatusCode.T
        @test StatusCode.INVALID_ARGUMENT isa StatusCode.T
        @test StatusCode.DEADLINE_EXCEEDED isa StatusCode.T
        @test StatusCode.NOT_FOUND isa StatusCode.T
        @test StatusCode.ALREADY_EXISTS isa StatusCode.T
        @test StatusCode.PERMISSION_DENIED isa StatusCode.T
        @test StatusCode.RESOURCE_EXHAUSTED isa StatusCode.T
        @test StatusCode.FAILED_PRECONDITION isa StatusCode.T
        @test StatusCode.ABORTED isa StatusCode.T
        @test StatusCode.OUT_OF_RANGE isa StatusCode.T
        @test StatusCode.UNIMPLEMENTED isa StatusCode.T
        @test StatusCode.INTERNAL isa StatusCode.T
        @test StatusCode.UNAVAILABLE isa StatusCode.T
        @test StatusCode.DATA_LOSS isa StatusCode.T
        @test StatusCode.UNAUTHENTICATED isa StatusCode.T

        # Verify numeric values match gRPC spec
        @test Int32(StatusCode.OK) == 0
        @test Int32(StatusCode.CANCELLED) == 1
        @test Int32(StatusCode.UNKNOWN) == 2
        @test Int32(StatusCode.INVALID_ARGUMENT) == 3
        @test Int32(StatusCode.DEADLINE_EXCEEDED) == 4
        @test Int32(StatusCode.NOT_FOUND) == 5
        @test Int32(StatusCode.ALREADY_EXISTS) == 6
        @test Int32(StatusCode.PERMISSION_DENIED) == 7
        @test Int32(StatusCode.RESOURCE_EXHAUSTED) == 8
        @test Int32(StatusCode.FAILED_PRECONDITION) == 9
        @test Int32(StatusCode.ABORTED) == 10
        @test Int32(StatusCode.OUT_OF_RANGE) == 11
        @test Int32(StatusCode.UNIMPLEMENTED) == 12
        @test Int32(StatusCode.INTERNAL) == 13
        @test Int32(StatusCode.UNAVAILABLE) == 14
        @test Int32(StatusCode.DATA_LOSS) == 15
        @test Int32(StatusCode.UNAUTHENTICATED) == 16
    end

    @testset "GRPCError Creation" begin
        # Basic error
        err = GRPCError(StatusCode.NOT_FOUND, "Resource not found")
        @test err.code == StatusCode.NOT_FOUND
        @test err.message == "Resource not found"
        @test isempty(err.details)

        # Error with details (using Any[] since that's what the constructor expects)
        details = Any[Dict("type" => "error_info", "domain" => "test")]
        err_with_details = GRPCError(StatusCode.INVALID_ARGUMENT, "Bad request", details)
        @test length(err_with_details.details) == 1
    end

    @testset "GRPCError Show" begin
        err = GRPCError(StatusCode.INTERNAL, "Something went wrong")
        str = sprint(showerror, err)
        @test occursin("GRPCError", str)
        @test occursin("INTERNAL", str)
        @test occursin("Something went wrong", str)
    end

    @testset "BindError" begin
        err = BindError("Failed to bind to 0.0.0.0:50051")
        @test err.message == "Failed to bind to 0.0.0.0:50051"
        @test err.cause === nothing

        # With cause
        cause = ErrorException("Address in use")
        err_with_cause = BindError("Failed to bind", cause)
        @test err_with_cause.cause === cause

        # Show method
        str = sprint(showerror, err_with_cause)
        @test occursin("BindError", str)
        @test occursin("Caused by", str)
    end

    @testset "InvalidServerStateError" begin
        err = InvalidServerStateError(:STOPPED, :RUNNING)
        @test err.expected == :STOPPED
        @test err.actual == :RUNNING

        str = sprint(showerror, err)
        @test occursin("InvalidServerStateError", str)
        @test occursin("STOPPED", str)
        @test occursin("RUNNING", str)
    end

    @testset "ServiceAlreadyRegisteredError" begin
        err = ServiceAlreadyRegisteredError("my.Service")
        @test err.service_name == "my.Service"

        str = sprint(showerror, err)
        @test occursin("ServiceAlreadyRegisteredError", str)
        @test occursin("my.Service", str)
    end

    @testset "MethodSignatureError" begin
        err = MethodSignatureError(
            "handler",
            "(ctx, request) -> response",
            "(ctx) -> response"
        )
        @test err.method_name == "handler"
        @test err.expected == "(ctx, request) -> response"
        @test err.actual == "(ctx) -> response"

        str = sprint(showerror, err)
        @test occursin("MethodSignatureError", str)
        @test occursin("handler", str)
    end

    @testset "StreamCancelledError" begin
        err = StreamCancelledError("Client disconnected")
        @test err.reason == "Client disconnected"

        str = sprint(showerror, err)
        @test occursin("StreamCancelledError", str)
        @test occursin("Client disconnected", str)
    end
end
