using gRPCServer

# Include generated types
include("generated/helloworld/helloworld.jl")
using .helloworld

# Handlers
function say_hello(ctx::ServerContext, request::HelloRequest)::HelloReply
    @info "Received request" name=request.name request_id=ctx.request_id
    HelloReply("Hello, $(request.name)!")
end

function say_hello_stream(
    ctx::ServerContext,
    request::HelloRequest,
    stream::ServerStream{HelloReply}
)::Nothing
    for i in 1:5
        if ctx.cancelled
            @warn "Stream cancelled by client"
            return nothing
        end
        send!(stream, HelloReply("Hello $(i), $(request.name)!"))
        sleep(0.5)
    end
    return nothing
end

# Service definition
struct GreeterService end

function gRPCServer.service_descriptor(::GreeterService)
    ServiceDescriptor(
        "helloworld.Greeter",
        Dict(
            "SayHello" => MethodDescriptor(
                "SayHello", MethodType.UNARY,
                HelloRequest, HelloReply,  # Use Julia types for auto-registration
                say_hello
            ),
            "SayHelloStream" => MethodDescriptor(
                "SayHelloStream", MethodType.SERVER_STREAMING,
                HelloRequest, HelloReply,  # Use Julia types for auto-registration
                say_hello_stream
            )
        ),
        nothing
    )
end

# Run server
function main()
    server = GRPCServer("127.0.0.1", 50051;
        enable_health_check = true,
        enable_reflection = true
    )

    register!(server, GreeterService())

    @info "gRPC server starting" host="127.0.0.1" port=50051
    run(server)
end

main()