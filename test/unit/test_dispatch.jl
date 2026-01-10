# Unit tests for dispatch and service registration

using Test
using gRPCServer

@testset "Dispatch Unit Tests" begin
    @testset "MethodDescriptor" begin
        handler = (ctx, req) -> "response"
        method = MethodDescriptor(
            "TestMethod",
            MethodType.UNARY,
            "test.TestRequest",
            "test.TestResponse",
            handler
        )

        @test method.name == "TestMethod"
        @test method.method_type == MethodType.UNARY
        @test method.input_type == "test.TestRequest"
        @test method.output_type == "test.TestResponse"
        @test method.handler === handler

        str = sprint(show, method)
        @test occursin("MethodDescriptor", str)
        @test occursin("TestMethod", str)
    end

    @testset "ServiceDescriptor" begin
        handler = (ctx, req) -> "response"
        methods = Dict(
            "Method1" => MethodDescriptor("Method1", MethodType.UNARY, "Req", "Resp", handler),
            "Method2" => MethodDescriptor("Method2", MethodType.SERVER_STREAMING, "Req", "Resp", handler)
        )

        service = ServiceDescriptor("test.TestService", methods)

        @test service.name == "test.TestService"
        @test length(service.methods) == 2
        @test service.file_descriptor === nothing

        # With file descriptor
        fd = UInt8[0x0a, 0x0b]
        service2 = ServiceDescriptor("test.Service", methods, fd)
        @test service2.file_descriptor == fd

        str = sprint(show, service)
        @test occursin("ServiceDescriptor", str)
        @test occursin("test.TestService", str)
        @test occursin("2 methods", str)
    end

    @testset "ServiceRegistry" begin
        registry = gRPCServer.ServiceRegistry()
        @test isempty(gRPCServer.list_services(registry))

        # Register a service
        handler = (ctx, req) -> "response"
        service = ServiceDescriptor(
            "test.TestService",
            Dict("Method" => MethodDescriptor("Method", MethodType.UNARY, "Req", "Resp", handler))
        )

        gRPCServer.register!(registry, service)
        @test "test.TestService" in gRPCServer.list_services(registry)

        # Cannot register same service twice
        @test_throws ServiceAlreadyRegisteredError gRPCServer.register!(registry, service)
    end

    @testset "Method Lookup" begin
        registry = gRPCServer.ServiceRegistry()

        handler = (ctx, req) -> "response"
        service = ServiceDescriptor(
            "test.TestService",
            Dict(
                "Method1" => MethodDescriptor("Method1", MethodType.UNARY, "Req", "Resp", handler),
                "Method2" => MethodDescriptor("Method2", MethodType.SERVER_STREAMING, "Req", "Resp", handler)
            )
        )

        gRPCServer.register!(registry, service)

        # Lookup by path
        result = gRPCServer.lookup_method(registry, "/test.TestService/Method1")
        @test result !== nothing
        svc, method = result
        @test svc.name == "test.TestService"
        @test method.name == "Method1"

        # Unknown method returns nothing
        @test gRPCServer.lookup_method(registry, "/test.TestService/Unknown") === nothing
        @test gRPCServer.lookup_method(registry, "/unknown.Service/Method") === nothing
    end

    @testset "RequestDispatcher Creation" begin
        dispatcher = gRPCServer.RequestDispatcher()
        @test !dispatcher.debug_mode

        dispatcher_debug = gRPCServer.RequestDispatcher(debug_mode=true)
        @test dispatcher_debug.debug_mode
    end

    @testset "RequestDispatcher Service Registration" begin
        dispatcher = gRPCServer.RequestDispatcher()

        handler = (ctx, req) -> "response"
        service = ServiceDescriptor(
            "test.TestService",
            Dict("Method" => MethodDescriptor("Method", MethodType.UNARY, "Req", "Resp", handler))
        )

        gRPCServer.register_service!(dispatcher, service)
        @test "test.TestService" in gRPCServer.list_services(dispatcher.registry)
    end

    @testset "RequestDispatcher Interceptors" begin
        dispatcher = gRPCServer.RequestDispatcher()

        # Add global interceptor
        gRPCServer.add_interceptor!(dispatcher, LoggingInterceptor())
        @test length(dispatcher.interceptor_chain) == 1

        # Add service-specific interceptor
        gRPCServer.add_interceptor!(dispatcher, "test.Service", MetricsInterceptor())
        @test haskey(dispatcher.service_interceptors, "test.Service")
    end

    @testset "parse_grpc_path" begin
        service, method = gRPCServer.parse_grpc_path("/test.TestService/Method")
        @test service == "test.TestService"
        @test method == "Method"

        # Invalid paths
        @test_throws GRPCError gRPCServer.parse_grpc_path("test.TestService/Method")  # No leading /
        @test_throws GRPCError gRPCServer.parse_grpc_path("/test.TestService")  # Missing method
    end

    @testset "serialize_message" begin
        # Raw bytes pass through
        data = UInt8[0x01, 0x02, 0x03]
        result = gRPCServer.serialize_message(data)

        # Should have 5-byte header + data
        @test length(result) == 5 + 3
        @test result[1] == 0  # Not compressed
        @test result[6:8] == data
    end

    @testset "deserialize_message" begin
        # Too short
        @test_throws GRPCError gRPCServer.deserialize_message(UInt8[0x00, 0x00], "test.Type")

        # Valid message (uncompressed, length 3, data [1,2,3])
        data = UInt8[0x00, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03]
        result = gRPCServer.deserialize_message(data, "test.Type")
        @test result == UInt8[0x01, 0x02, 0x03]

        # Truncated message
        short_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x05, 0x01, 0x02]  # Claims 5 bytes, only 2
        @test_throws GRPCError gRPCServer.deserialize_message(short_data, "test.Type")
    end
end
