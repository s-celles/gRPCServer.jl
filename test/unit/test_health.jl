# Unit tests for health checking service

using Test
using gRPCServer

@testset "Health Service Unit Tests" begin
    @testset "HealthStatus Enum" begin
        @test HealthStatus.UNKNOWN isa HealthStatus.T
        @test HealthStatus.SERVING isa HealthStatus.T
        @test HealthStatus.NOT_SERVING isa HealthStatus.T
        @test HealthStatus.SERVICE_UNKNOWN isa HealthStatus.T

        # Verify numeric values match gRPC spec
        @test Int(HealthStatus.UNKNOWN) == 0
        @test Int(HealthStatus.SERVING) == 1
        @test Int(HealthStatus.NOT_SERVING) == 2
        @test Int(HealthStatus.SERVICE_UNKNOWN) == 3
    end

    @testset "HealthCheckRequest" begin
        req = gRPCServer.HealthCheckRequest()
        @test req.service == ""

        req2 = gRPCServer.HealthCheckRequest(service="my.Service")
        @test req2.service == "my.Service"
    end

    @testset "HealthCheckResponse" begin
        resp = gRPCServer.HealthCheckResponse()
        @test resp.status == HealthStatus.UNKNOWN

        resp2 = gRPCServer.HealthCheckResponse(status=HealthStatus.SERVING)
        @test resp2.status == HealthStatus.SERVING
    end

    @testset "health_check Function" begin
        # Mock get_health function
        health_status = Dict(
            "" => HealthStatus.SERVING,
            "my.Service" => HealthStatus.NOT_SERVING
        )
        get_health = (service) -> get(health_status, service, HealthStatus.SERVICE_UNKNOWN)

        ctx = ServerContext()

        # Check overall health
        req1 = gRPCServer.HealthCheckRequest(service="")
        resp1 = gRPCServer.health_check(ctx, req1, get_health)
        @test resp1.status == HealthStatus.SERVING

        # Check specific service
        req2 = gRPCServer.HealthCheckRequest(service="my.Service")
        resp2 = gRPCServer.health_check(ctx, req2, get_health)
        @test resp2.status == HealthStatus.NOT_SERVING

        # Check unknown service
        req3 = gRPCServer.HealthCheckRequest(service="unknown.Service")
        resp3 = gRPCServer.health_check(ctx, req3, get_health)
        @test resp3.status == HealthStatus.SERVICE_UNKNOWN
    end

    @testset "create_health_service" begin
        server = GRPCServer("0.0.0.0", 50051)
        descriptor = gRPCServer.create_health_service(server)

        @test descriptor.name == "grpc.health.v1.Health"
        @test haskey(descriptor.methods, "Check")
        @test haskey(descriptor.methods, "Watch")

        # Check method types
        @test descriptor.methods["Check"].method_type == MethodType.UNARY
        @test descriptor.methods["Watch"].method_type == MethodType.SERVER_STREAMING
    end

    @testset "Server Health Management" begin
        server = GRPCServer("0.0.0.0", 50051)

        # Set overall health
        set_health!(server, HealthStatus.SERVING)
        @test get_health(server) == HealthStatus.SERVING

        # Set to not serving
        set_health!(server, HealthStatus.NOT_SERVING)
        @test get_health(server) == HealthStatus.NOT_SERVING

        # Set service-specific health
        set_health!(server, "my.Service", HealthStatus.SERVING)
        @test get_health(server, "my.Service") == HealthStatus.SERVING

        # Unknown service
        @test get_health(server, "unknown") == HealthStatus.SERVICE_UNKNOWN
    end
end
