# Unit tests for interceptors

using Test
using gRPCServer

@testset "Interceptor Unit Tests" begin
    @testset "MethodInfo" begin
        info = MethodInfo("test.Service", "TestMethod", MethodType.UNARY)
        @test info.service_name == "test.Service"
        @test info.method_name == "TestMethod"
        @test info.method_type == MethodType.UNARY

        str = sprint(show, info)
        @test occursin("MethodInfo", str)
    end

    @testset "LoggingInterceptor" begin
        interceptor = LoggingInterceptor()
        @test interceptor.log_requests == true
        @test interceptor.log_responses == true
        @test interceptor.log_errors == true

        # Custom configuration
        interceptor2 = LoggingInterceptor(log_requests=false)
        @test interceptor2.log_requests == false
    end

    @testset "MetricsInterceptor" begin
        request_count = Ref(0)
        response_count = Ref(0)

        interceptor = MetricsInterceptor(
            on_request = (method, size) -> request_count[] += 1,
            on_response = (method, status, ms, size) -> response_count[] += 1
        )

        # Create a simple handler
        handler = (ctx, req) -> "response"
        info = MethodInfo("test.Service", "Test", MethodType.UNARY)
        ctx = ServerContext()

        # Execute interceptor
        result = interceptor(ctx, "request", info, handler)

        @test result == "response"
        @test request_count[] == 1
        @test response_count[] == 1
    end

    @testset "TimeoutInterceptor" begin
        interceptor = TimeoutInterceptor(default_timeout_ms=5000)
        @test interceptor.default_timeout_ms == 5000

        # No default timeout
        interceptor2 = TimeoutInterceptor()
        @test interceptor2.default_timeout_ms === nothing
    end

    @testset "RecoveryInterceptor" begin
        interceptor = RecoveryInterceptor()
        @test interceptor.include_stack_trace == false

        interceptor2 = RecoveryInterceptor(include_stack_trace=true)
        @test interceptor2.include_stack_trace == true

        # Test recovery from exception
        handler = (ctx, req) -> error("Unexpected error")
        info = MethodInfo("test.Service", "Test", MethodType.UNARY)
        ctx = ServerContext()

        @test_throws GRPCError interceptor(ctx, "request", info, handler)

        # Test pass-through of GRPCError
        handler2 = (ctx, req) -> throw(GRPCError(StatusCode.NOT_FOUND, "Not found"))
        @test_throws GRPCError interceptor(ctx, "request", info, handler2)
    end

    @testset "MethodType Enum" begin
        @test MethodType.UNARY isa MethodType.T
        @test MethodType.SERVER_STREAMING isa MethodType.T
        @test MethodType.CLIENT_STREAMING isa MethodType.T
        @test MethodType.BIDI_STREAMING isa MethodType.T
    end
end
