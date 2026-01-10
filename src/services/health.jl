# gRPC Health Checking Service for gRPCServer.jl
# Per https://github.com/grpc/grpc/blob/master/doc/health-checking.md

"""
    HealthCheckRequest

Request message for health check.
"""
struct HealthCheckRequest
    service::String

    HealthCheckRequest(; service::String="") = new(service)
end

"""
    HealthCheckResponse

Response message for health check.
"""
struct HealthCheckResponse
    status::HealthStatus.T

    HealthCheckResponse(; status::HealthStatus.T=HealthStatus.UNKNOWN) = new(status)
end

"""
    HealthService

Implementation of the gRPC Health Checking protocol.
"""
struct HealthService
    get_health::Function  # (service_name) -> HealthStatus.T

    HealthService(get_health::Function) = new(get_health)
end

"""
    health_check(ctx::ServerContext, request::HealthCheckRequest, get_health::Function) -> HealthCheckResponse

Handle Health.Check unary RPC.
"""
function health_check(ctx::ServerContext, request::HealthCheckRequest, get_health::Function)::HealthCheckResponse
    status = get_health(request.service)
    return HealthCheckResponse(status=status)
end

"""
    health_watch(ctx::ServerContext, request::HealthCheckRequest, stream::ServerStream{HealthCheckResponse}, get_health::Function)

Handle Health.Watch streaming RPC.
Sends health status updates when they change.
"""
function health_watch(
    ctx::ServerContext,
    request::HealthCheckRequest,
    stream::ServerStream{HealthCheckResponse},
    get_health::Function
)
    last_status = nothing

    while !is_cancelled(ctx)
        current_status = get_health(request.service)

        if current_status != last_status
            send!(stream, HealthCheckResponse(status=current_status))
            last_status = current_status
        end

        sleep(1.0)  # Check every second
    end
end

"""
    create_health_service(server::GRPCServer) -> ServiceDescriptor

Create the health service descriptor for a server.
"""
function create_health_service(server)::ServiceDescriptor
    get_health = (service_name) -> get(server.health_status, service_name, HealthStatus.SERVICE_UNKNOWN)

    return ServiceDescriptor(
        "grpc.health.v1.Health",
        Dict(
            "Check" => MethodDescriptor(
                "Check",
                MethodType.UNARY,
                "grpc.health.v1.HealthCheckRequest",
                "grpc.health.v1.HealthCheckResponse",
                (ctx, req) -> health_check(ctx, req, get_health)
            ),
            "Watch" => MethodDescriptor(
                "Watch",
                MethodType.SERVER_STREAMING,
                "grpc.health.v1.HealthCheckRequest",
                "grpc.health.v1.HealthCheckResponse",
                (ctx, req, stream) -> health_watch(ctx, req, stream, get_health)
            )
        ),
        nothing  # File descriptor for reflection (would be set from compiled proto)
    )
end
