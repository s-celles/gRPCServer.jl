# gRPC Server Reflection Service for gRPCServer.jl
# Per https://github.com/grpc/grpc/blob/master/doc/server-reflection.md
#
# Note: The protobuf types (ServerReflectionRequest, ServerReflectionResponse, etc.)
# are defined in proto/grpc/reflection/v1alpha/reflection_pb.jl

using ProtoBuf: OneOf

"""
    ReflectionService

Implementation of the gRPC Server Reflection protocol.
"""
struct ReflectionService
    registry::ServiceRegistry
end

"""
    server_reflection_info(
        ctx::ServerContext,
        stream::BidiStream{ServerReflectionRequest, ServerReflectionResponse},
        registry::ServiceRegistry
    )

Handle ServerReflection.ServerReflectionInfo bidirectional streaming RPC.
"""
function server_reflection_info(
    ctx::ServerContext,
    stream::BidiStream{ServerReflectionRequest, ServerReflectionResponse},
    registry::ServiceRegistry
)
    for request in stream
        response = handle_reflection_request(request, registry)
        send!(stream, response)
    end
end

"""
    handle_reflection_request(request::ServerReflectionRequest, registry::ServiceRegistry) -> ServerReflectionResponse

Process a single reflection request.
"""
function handle_reflection_request(
    request::ServerReflectionRequest,
    registry::ServiceRegistry
)::ServerReflectionResponse
    if request.message_request !== nothing && request.message_request.name === :list_services
        # List all services
        services = [ServiceResponse(name) for name in list_services(registry)]
        list_response = ListServiceResponse(services)
        return ServerReflectionResponse(
            request.host,
            request,
            OneOf(:list_services_response, list_response)
        )
    elseif request.message_request !== nothing && request.message_request.name === :file_containing_symbol
        # Find file descriptor containing symbol
        symbol = request.message_request[]::String

        # Look up service
        service = get_service(registry, symbol)
        if service !== nothing && service.file_descriptor !== nothing
            fd_response = FileDescriptorResponse([service.file_descriptor])
            return ServerReflectionResponse(
                request.host,
                request,
                OneOf(:file_descriptor_response, fd_response)
            )
        end

        # Symbol not found
        error_resp = ErrorResponse(Int32(5), "Symbol not found: $symbol")  # NOT_FOUND = 5
        return ServerReflectionResponse(
            request.host,
            request,
            OneOf(:error_response, error_resp)
        )
    elseif request.message_request !== nothing && request.message_request.name === :file_by_filename
        # Find file descriptor by filename
        filename = request.message_request[]::String

        # Search all services for matching file descriptor
        for (_, service) in registry.services
            if service.file_descriptor !== nothing
                # Would check filename in descriptor
                fd_response = FileDescriptorResponse([service.file_descriptor])
                return ServerReflectionResponse(
                    request.host,
                    request,
                    OneOf(:file_descriptor_response, fd_response)
                )
            end
        end

        error_resp = ErrorResponse(Int32(5), "File not found: $filename")  # NOT_FOUND = 5
        return ServerReflectionResponse(
            request.host,
            request,
            OneOf(:error_response, error_resp)
        )
    else
        error_resp = ErrorResponse(Int32(3), "Unknown request type")  # INVALID_ARGUMENT = 3
        return ServerReflectionResponse(
            request.host,
            request,
            OneOf(:error_response, error_resp)
        )
    end
end

"""
    create_reflection_service(registry::ServiceRegistry) -> ServiceDescriptor

Create the reflection service descriptor.
"""
function create_reflection_service(registry::ServiceRegistry)::ServiceDescriptor
    return ServiceDescriptor(
        "grpc.reflection.v1alpha.ServerReflection",
        Dict(
            "ServerReflectionInfo" => MethodDescriptor(
                "ServerReflectionInfo",
                MethodType.BIDI_STREAMING,
                "grpc.reflection.v1alpha.ServerReflectionRequest",
                "grpc.reflection.v1alpha.ServerReflectionResponse",
                (ctx, stream) -> server_reflection_info(ctx, stream, registry)
            )
        ),
        nothing  # File descriptor would be set from compiled proto
    )
end
