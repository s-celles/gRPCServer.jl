# Integration tests for health checking service
# Tests end-to-end health check functionality

using Test
using gRPCServer

# TestUtils is included once in runtests.jl to avoid method redefinition warnings
# using TestUtils is inherited from the parent module

@testset "Health Service Integration Tests" begin
    @testset "Health Service Registration" begin
        with_test_server(enable_health_check=true) do ts
            # Health service should be auto-registered
            @test gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.health.v1.Health/Check"
            ) !== nothing

            @test gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.health.v1.Health/Watch"
            ) !== nothing
        end
    end

    @testset "Health Status Management" begin
        server = GRPCServer("127.0.0.1", 50100)

        # Initial status
        @test get_health(server) == HealthStatus.SERVICE_UNKNOWN

        # Set overall server health
        set_health!(server, HealthStatus.SERVING)
        @test get_health(server) == HealthStatus.SERVING

        # Set service-specific health
        set_health!(server, "my.Service", HealthStatus.NOT_SERVING)
        @test get_health(server, "my.Service") == HealthStatus.NOT_SERVING

        # Overall health unaffected
        @test get_health(server) == HealthStatus.SERVING

        # Unknown service
        @test get_health(server, "unknown.Service") == HealthStatus.SERVICE_UNKNOWN
    end

    @testset "Health Status Enum Values" begin
        @test Int(HealthStatus.UNKNOWN) == 0
        @test Int(HealthStatus.SERVING) == 1
        @test Int(HealthStatus.NOT_SERVING) == 2
        @test Int(HealthStatus.SERVICE_UNKNOWN) == 3
    end

    @testset "HealthCheckRequest/Response Types" begin
        # Test request type
        req = gRPCServer.HealthCheckRequest(service="my.Service")
        @test req.service == "my.Service"

        req_empty = gRPCServer.HealthCheckRequest()
        @test req_empty.service == ""

        # Test response type
        resp = gRPCServer.HealthCheckResponse(status=HealthStatus.SERVING)
        @test resp.status == HealthStatus.SERVING
    end

    @testset "Health Check Handler" begin
        health_status = Dict{String, HealthStatus.T}(
            "" => HealthStatus.SERVING,
            "my.Service" => HealthStatus.NOT_SERVING
        )

        get_health_fn = (service) -> get(health_status, service, HealthStatus.SERVICE_UNKNOWN)

        # Check overall health
        req = gRPCServer.HealthCheckRequest()
        ctx = ServerContext()
        resp = gRPCServer.health_check(ctx, req, get_health_fn)
        @test resp.status == HealthStatus.SERVING

        # Check specific service
        req2 = gRPCServer.HealthCheckRequest(service="my.Service")
        resp2 = gRPCServer.health_check(ctx, req2, get_health_fn)
        @test resp2.status == HealthStatus.NOT_SERVING

        # Check unknown service
        req3 = gRPCServer.HealthCheckRequest(service="unknown.Service")
        resp3 = gRPCServer.health_check(ctx, req3, get_health_fn)
        @test resp3.status == HealthStatus.SERVICE_UNKNOWN
    end

    @testset "Health Check Method Resolution" begin
        with_test_server(enable_health_check=true) do ts
            result = gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.health.v1.Health/Check"
            )
            @test result !== nothing

            _, method = result
            @test method.method_type == MethodType.UNARY
            @test method.name == "Check"
        end
    end

    @testset "Health Watch Method Resolution" begin
        with_test_server(enable_health_check=true) do ts
            result = gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.health.v1.Health/Watch"
            )
            @test result !== nothing

            _, method = result
            @test method.method_type == MethodType.SERVER_STREAMING
            @test method.name == "Watch"
        end
    end

    @testset "Service Health Initialization" begin
        handler = (ctx, req) -> req

        descriptor = ServiceDescriptor(
            "test.MyService",
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

        server = GRPCServer("127.0.0.1", 50101)

        # Register service
        gRPCServer.register_service!(server.dispatcher, descriptor)
        server.health_status[descriptor.name] = HealthStatus.SERVING

        # Service should be marked as SERVING
        @test get_health(server, "test.MyService") == HealthStatus.SERVING
    end

    @testset "Health Status Transitions" begin
        server = GRPCServer("127.0.0.1", 50102)

        # Transition through states
        set_health!(server, HealthStatus.UNKNOWN)
        @test get_health(server) == HealthStatus.UNKNOWN

        set_health!(server, HealthStatus.SERVING)
        @test get_health(server) == HealthStatus.SERVING

        set_health!(server, HealthStatus.NOT_SERVING)
        @test get_health(server) == HealthStatus.NOT_SERVING

        # Back to serving
        set_health!(server, HealthStatus.SERVING)
        @test get_health(server) == HealthStatus.SERVING
    end

    @testset "Multiple Services Health" begin
        server = GRPCServer("127.0.0.1", 50103)

        services = ["svc.A", "svc.B", "svc.C"]

        # All start as unknown
        for svc in services
            @test get_health(server, svc) == HealthStatus.SERVICE_UNKNOWN
        end

        # Set different statuses
        set_health!(server, "svc.A", HealthStatus.SERVING)
        set_health!(server, "svc.B", HealthStatus.NOT_SERVING)
        set_health!(server, "svc.C", HealthStatus.UNKNOWN)

        @test get_health(server, "svc.A") == HealthStatus.SERVING
        @test get_health(server, "svc.B") == HealthStatus.NOT_SERVING
        @test get_health(server, "svc.C") == HealthStatus.UNKNOWN
    end

    @testset "Health with Live Server" begin
        with_test_server(enable_health_check=true) do ts
            # Set health status
            set_health!(ts.server, HealthStatus.SERVING)
            @test get_health(ts.server) == HealthStatus.SERVING

            # Server should be running
            @test ts.server.status == ServerStatus.RUNNING

            # Test connection
            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            disconnect!(client)
        end
    end

    @testset "Health Service Descriptor" begin
        server = GRPCServer("127.0.0.1", 50104)
        descriptor = gRPCServer.create_health_service(server)

        @test descriptor.name == "grpc.health.v1.Health"
        @test haskey(descriptor.methods, "Check")
        @test haskey(descriptor.methods, "Watch")
        @test descriptor.methods["Check"].method_type == MethodType.UNARY
        @test descriptor.methods["Watch"].method_type == MethodType.SERVER_STREAMING
    end
end
