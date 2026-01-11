# Unit tests for reflection service

using Test
using gRPCServer
using ProtoBuf: OneOf

@testset "Reflection Service Unit Tests" begin
    @testset "ServerReflectionRequest Creation" begin
        # Default request (with nothing message_request)
        req = gRPCServer.ServerReflectionRequest("", nothing)
        @test req.host == ""
        @test req.message_request === nothing

        # List services request
        req_list = gRPCServer.ServerReflectionRequest("", OneOf(:list_services, ""))
        @test req_list.message_request !== nothing
        @test req_list.message_request.name === :list_services

        # File containing symbol request
        req_symbol = gRPCServer.ServerReflectionRequest(
            "",
            OneOf(:file_containing_symbol, "my.Service")
        )
        @test req_symbol.message_request !== nothing
        @test req_symbol.message_request.name === :file_containing_symbol
        @test req_symbol.message_request[] == "my.Service"
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
        req = gRPCServer.ServerReflectionRequest("localhost", nothing)

        # List services response
        list_services_resp = gRPCServer.ListServiceResponse([
            gRPCServer.ServiceResponse("test.Service")
        ])
        resp = gRPCServer.ServerReflectionResponse(
            "localhost",
            req,
            OneOf(:list_services_response, list_services_resp)
        )
        @test resp.valid_host == "localhost"
        @test resp.message_response !== nothing
        @test resp.message_response.name === :list_services_response

        # Error response
        err = gRPCServer.ErrorResponse(Int32(5), "Symbol not found")
        err_resp = gRPCServer.ServerReflectionResponse(
            "localhost",
            req,
            OneOf(:error_response, err)
        )
        @test err_resp.message_response !== nothing
        @test err_resp.message_response.name === :error_response
        @test err_resp.message_response[].error_message == "Symbol not found"
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
        req = gRPCServer.ServerReflectionRequest("", OneOf(:list_services, "*"))
        resp = gRPCServer.handle_reflection_request(req, registry)

        @test resp.message_response !== nothing
        @test resp.message_response.name === :list_services_response
        list_resp = resp.message_response[]
        @test length(list_resp.service) >= 1

        # Find our test service in the response
        service_names = [s.name for s in list_resp.service]
        @test "test.TestService" in service_names
    end

    @testset "handle_reflection_request - file_containing_symbol (not found)" begin
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        req = gRPCServer.ServerReflectionRequest(
            "",
            OneOf(:file_containing_symbol, "nonexistent.Service")
        )
        resp = gRPCServer.handle_reflection_request(req, registry)

        @test resp.message_response !== nothing
        @test resp.message_response.name === :error_response
        @test occursin("not found", resp.message_response[].error_message)
    end

    @testset "handle_reflection_request - unknown request type" begin
        server = GRPCServer("0.0.0.0", 50051)
        registry = server.dispatcher.registry

        # Empty request (no specific request type)
        req = gRPCServer.ServerReflectionRequest("", nothing)
        resp = gRPCServer.handle_reflection_request(req, registry)

        @test resp.message_response !== nothing
        @test resp.message_response.name === :error_response
        @test occursin("Unknown", resp.message_response[].error_message)
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
