# gRPC Server Reflection Service for gRPCServer.jl
# Per https://github.com/grpc/grpc/blob/master/doc/server-reflection.md

"""
    ServerReflectionRequest

Request message for server reflection.
"""
struct ServerReflectionRequest
    host::String
    file_by_filename::Union{String, Nothing}
    file_containing_symbol::Union{String, Nothing}
    file_containing_extension::Union{Nothing, Any}
    all_extension_numbers_of_type::Union{String, Nothing}
    list_services::Union{String, Nothing}

    function ServerReflectionRequest(;
        host::String="",
        file_by_filename::Union{String, Nothing}=nothing,
        file_containing_symbol::Union{String, Nothing}=nothing,
        file_containing_extension::Union{Nothing, Any}=nothing,
        all_extension_numbers_of_type::Union{String, Nothing}=nothing,
        list_services::Union{String, Nothing}=nothing
    )
        new(host, file_by_filename, file_containing_symbol,
            file_containing_extension, all_extension_numbers_of_type, list_services)
    end
end

"""
    ServiceResponse

Response containing service information.
"""
struct ServiceResponse
    name::String
end

"""
    ListServiceResponse

Response containing list of services.
"""
struct ListServiceResponse
    service::Vector{ServiceResponse}
end

"""
    ServerReflectionResponse

Response message for server reflection.
"""
struct ServerReflectionResponse
    valid_host::String
    original_request::ServerReflectionRequest
    file_descriptor_response::Union{Vector{Vector{UInt8}}, Nothing}
    all_extension_numbers_response::Union{Vector{Int32}, Nothing}
    list_services_response::Union{ListServiceResponse, Nothing}
    error_response::Union{String, Nothing}

    function ServerReflectionResponse(;
        valid_host::String="",
        original_request::ServerReflectionRequest=ServerReflectionRequest(),
        file_descriptor_response::Union{Vector{Vector{UInt8}}, Nothing}=nothing,
        all_extension_numbers_response::Union{Vector{Int32}, Nothing}=nothing,
        list_services_response::Union{ListServiceResponse, Nothing}=nothing,
        error_response::Union{String, Nothing}=nothing
    )
        new(valid_host, original_request, file_descriptor_response,
            all_extension_numbers_response, list_services_response, error_response)
    end
end

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
    if request.list_services !== nothing
        # List all services
        services = [ServiceResponse(name) for name in list_services(registry)]
        return ServerReflectionResponse(
            valid_host=request.host,
            original_request=request,
            list_services_response=ListServiceResponse(services)
        )
    elseif request.file_containing_symbol !== nothing
        # Find file descriptor containing symbol
        symbol = request.file_containing_symbol

        # Look up service
        service = get_service(registry, symbol)
        if service !== nothing && service.file_descriptor !== nothing
            return ServerReflectionResponse(
                valid_host=request.host,
                original_request=request,
                file_descriptor_response=[service.file_descriptor]
            )
        end

        # Symbol not found
        return ServerReflectionResponse(
            valid_host=request.host,
            original_request=request,
            error_response="Symbol not found: $symbol"
        )
    elseif request.file_by_filename !== nothing
        # Find file descriptor by filename
        filename = request.file_by_filename

        # Search all services for matching file descriptor
        for (_, service) in registry.services
            if service.file_descriptor !== nothing
                # Would check filename in descriptor
                return ServerReflectionResponse(
                    valid_host=request.host,
                    original_request=request,
                    file_descriptor_response=[service.file_descriptor]
                )
            end
        end

        return ServerReflectionResponse(
            valid_host=request.host,
            original_request=request,
            error_response="File not found: $filename"
        )
    else
        return ServerReflectionResponse(
            valid_host=request.host,
            original_request=request,
            error_response="Unknown request type"
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
