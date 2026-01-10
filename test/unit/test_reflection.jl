# Unit tests for reflection service

using Test
using gRPCServer

@testset "Reflection Service Unit Tests" begin
    @testset "ServerReflectionRequest Creation" begin
        # Default request
        req = gRPCServer.ServerReflectionRequest()
        @test req.host == ""
        @test req.file_by_filename === nothing
        @test req.file_containing_symbol === nothing
        @test req.list_services === nothing

        # List services request
        req_list = gRPCServer.ServerReflectionRequest(list_services="")
        @test req_list.list_services == ""

        # File containing symbol request
        req_symbol = gRPCServer.ServerReflectionRequest(
            file_containing_symbol="my.Service"
        )
        @test req_symbol.file_containing_symbol == "my.Service"
    end

    @testset "ServiceResponse Creation" begin
        resp = gRPCServer.ServiceResponse("my.Service")
        @test resp.name == "my.Service"
    end

    @testset "ListServiceResponse Creation" begin
        services = [
            gRPCServer.ServiceResponse("service1"),
            gRPCServer.ServiceResponse("service2")
        ]
        list_resp = gRPCServer.ListServiceResponse(services)
        @test length(list_resp.service) == 2
        @test list_resp.service[1].name == "service1"
        @test list_resp.service[2].name == "service2"
    end

    @testset "ServerReflectionResponse Creation" begin
        req = gRPCServer.ServerReflectionRequest(host="localhost")

        # List services response
        resp = gRPCServer.ServerReflectionResponse(
            valid_host="localhost",
            original_request=req,
            list_services_response=gRPCServer.ListServiceResponse([
                gRPCServer.ServiceResponse("test.Service")
            ])
        )
        @test resp.valid_host == "localhost"
        @test resp.list_services_response !== nothing
        @test resp.error_response === nothing

        # Error response
        err_resp = gRPCServer.ServerReflectionResponse(
            valid_host="localhost",
            original_request=req,
            error_response="Symbol not found"
        )
        @test err_resp.error_response == "Symbol not found"
    end

    @testset "ReflectionService Creation" begin
        # Create a dispatcher and registry
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        reflection = gRPCServer.ReflectionService(registry)
        @test reflection.registry === registry
    end

    @testset "handle_reflection_request - list_services" begin
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        # Register a test service
        descriptor = ServiceDescriptor(
            "test.TestService",
            Dict(
                "TestMethod" => MethodDescriptor(
                    "TestMethod",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    (ctx, req) -> req
                )
            ),
            nothing
        )
        gRPCServer.register!(registry, descriptor)

        # Create list services request
        req = gRPCServer.ServerReflectionRequest(list_services="")
        resp = gRPCServer.handle_reflection_request(req, registry)

        @test resp.list_services_response !== nothing
        @test length(resp.list_services_response.service) >= 1

        # Find our test service in the response
        service_names = [s.name for s in resp.list_services_response.service]
        @test "test.TestService" in service_names
    end

    @testset "handle_reflection_request - file_containing_symbol (not found)" begin
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        req = gRPCServer.ServerReflectionRequest(
            file_containing_symbol="nonexistent.Service"
        )
        resp = gRPCServer.handle_reflection_request(req, registry)

        @test resp.error_response !== nothing
        @test occursin("not found", resp.error_response)
    end

    @testset "handle_reflection_request - unknown request type" begin
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        # Empty request (no specific request type)
        req = gRPCServer.ServerReflectionRequest()
        resp = gRPCServer.handle_reflection_request(req, registry)

        @test resp.error_response !== nothing
        @test occursin("Unknown", resp.error_response)
    end

    @testset "create_reflection_service" begin
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        descriptor = gRPCServer.create_reflection_service(registry)

        @test descriptor.name == "grpc.reflection.v1alpha.ServerReflection"
        @test haskey(descriptor.methods, "ServerReflectionInfo")

        method = descriptor.methods["ServerReflectionInfo"]
        @test method.method_type == MethodType.BIDI_STREAMING
    end

    @testset "Server with reflection enabled" begin
        server = GRPCServer("0.0.0.0", 50051; enable_reflection = true)
        @test server.config.enable_reflection == true
    end
end
