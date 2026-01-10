# Integration tests for interceptors
# Tests end-to-end interceptor chain execution

using Test
using gRPCServer

include("test_utils.jl")

@testset "Interceptor Integration Tests" begin
    @testset "Single Interceptor Execution" begin
        interceptor_called = Ref(false)

        struct TestInterceptor <: Interceptor end

        function (::TestInterceptor)(ctx, request, info, next)
            interceptor_called[] = true
            return next(ctx, request)
        end

        handler = (ctx, req) -> req

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, TestInterceptor())

        descriptor = ServiceDescriptor(
            "test.InterceptorService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.InterceptorService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test interceptor_called[]
    end

    @testset "Interceptor Chain Order" begin
        execution_order = String[]

        struct OrderInterceptor <: Interceptor
            name::String
        end

        function (i::OrderInterceptor)(ctx, request, info, next)
            push!(execution_order, "before_$(i.name)")
            result = next(ctx, request)
            push!(execution_order, "after_$(i.name)")
            return result
        end

        handler = (ctx, req) -> begin
            push!(execution_order, "handler")
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, OrderInterceptor("first"))
        gRPCServer.add_interceptor!(dispatcher, OrderInterceptor("second"))
        gRPCServer.add_interceptor!(dispatcher, OrderInterceptor("third"))

        descriptor = ServiceDescriptor(
            "test.OrderService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.OrderService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        empty!(execution_order)
        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test execution_order == [
            "before_first", "before_second", "before_third",
            "handler",
            "after_third", "after_second", "after_first"
        ]
    end

    @testset "Interceptor Short-Circuit" begin
        handler_called = Ref(false)

        struct ShortCircuitInterceptor <: Interceptor end

        function (::ShortCircuitInterceptor)(ctx, request, info, next)
            # Don't call next() - short circuit
            return UInt8[0xFF]  # Return custom response
        end

        handler = (ctx, req) -> begin
            handler_called[] = true
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, ShortCircuitInterceptor())

        descriptor = ServiceDescriptor(
            "test.ShortCircuitService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ShortCircuitService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        handler_called[] = false
        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test !handler_called[]  # Handler should not be called
    end

    @testset "Interceptor Error Handling" begin
        struct ErrorInterceptor <: Interceptor end

        function (::ErrorInterceptor)(ctx, request, info, next)
            throw(GRPCError(StatusCode.PERMISSION_DENIED, "Access denied"))
        end

        handler = (ctx, req) -> req

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, ErrorInterceptor())

        descriptor = ServiceDescriptor(
            "test.ErrorInterceptorService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ErrorInterceptorService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        status, message, _ = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test status == StatusCode.PERMISSION_DENIED
        @test message == "Access denied"
    end

    @testset "Service-Specific Interceptor" begin
        global_called = Ref(false)
        service_called = Ref(false)

        struct GlobalInterceptor <: Interceptor end
        struct ServiceInterceptor <: Interceptor end

        function (::GlobalInterceptor)(ctx, request, info, next)
            global_called[] = true
            return next(ctx, request)
        end

        function (::ServiceInterceptor)(ctx, request, info, next)
            service_called[] = true
            return next(ctx, request)
        end

        handler = (ctx, req) -> req

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, GlobalInterceptor())
        gRPCServer.add_interceptor!(dispatcher, "test.SpecificService", ServiceInterceptor())

        descriptor = ServiceDescriptor(
            "test.SpecificService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.SpecificService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        global_called[] = false
        service_called[] = false
        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test global_called[]
        @test service_called[]
    end

    @testset "Built-in LoggingInterceptor" begin
        # Just verify it can be created and added
        interceptor = LoggingInterceptor()
        @test interceptor.log_requests
        @test interceptor.log_responses
        @test interceptor.log_errors

        interceptor_custom = LoggingInterceptor(
            log_requests=false,
            log_responses=true,
            log_errors=false
        )
        @test !interceptor_custom.log_requests
        @test interceptor_custom.log_responses
        @test !interceptor_custom.log_errors
    end

    @testset "Built-in MetricsInterceptor" begin
        request_metrics = []
        response_metrics = []

        interceptor = MetricsInterceptor(
            on_request = (method, size) -> push!(request_metrics, (method, size)),
            on_response = (method, status, duration, size) -> push!(response_metrics, (method, status))
        )

        handler = (ctx, req) -> req

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, interceptor)

        descriptor = ServiceDescriptor(
            "test.MetricsService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.MetricsService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test length(request_metrics) == 1
        @test request_metrics[1][1] == "test.MetricsService/Test"
        @test length(response_metrics) == 1
        @test response_metrics[1][2] == StatusCode.OK
    end

    @testset "Built-in RecoveryInterceptor" begin
        handler = (ctx, req) -> throw(ErrorException("Unexpected error"))

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, RecoveryInterceptor())

        descriptor = ServiceDescriptor(
            "test.RecoveryService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.RecoveryService/Test")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        status, message, _ = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test status == StatusCode.INTERNAL
    end

    @testset "Interceptors with Streaming" begin
        interceptor_count = Ref(0)

        struct StreamInterceptor <: Interceptor end

        function (::StreamInterceptor)(ctx, stream, info, next)
            interceptor_count[] += 1
            return next(ctx, stream)
        end

        handler = (ctx, stream) -> begin
            count = 0
            for _ in stream
                count += 1
            end
            return UInt8[UInt8(count)]
        end

        dispatcher = gRPCServer.RequestDispatcher()
        gRPCServer.add_interceptor!(dispatcher, StreamInterceptor())

        descriptor = ServiceDescriptor(
            "test.StreamInterceptorService",
            Dict(
                "Test" => MethodDescriptor(
                    "Test",
                    MethodType.CLIENT_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.StreamInterceptorService/Test")

        messages = [UInt8[0x01], nothing]
        idx = Ref(1)
        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        is_cancelled_callback = () -> false

        interceptor_count[] = 0
        gRPCServer.dispatch_client_streaming(dispatcher, ctx, receive_callback, is_cancelled_callback)

        @test interceptor_count[] == 1
    end

    @testset "Interceptors with Live Server" begin
        with_test_server(log_requests=true) do ts
            # Log requests flag should add logging interceptor
            @test length(ts.server.dispatcher.interceptor_chain) >= 1

            @test ts.server.status == ServerStatus.RUNNING

            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            disconnect!(client)
        end
    end
end
