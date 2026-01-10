# Quick Start

This guide demonstrates how to create a gRPC server in Julia using gRPCServer.jl.

## Prerequisites

- Julia 1.10 or later
- ProtoBuf.jl for message type generation

## Installation

```julia
using Pkg
Pkg.add("gRPCServer")
```

## Step 1: Define Your Service

Create a `.proto` file defining your service:

```protobuf
// greeter.proto
syntax = "proto3";

package helloworld;

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply);
  rpc SayHelloStream (HelloRequest) returns (stream HelloReply);
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

## Step 2: Generate Julia Types

Use ProtoBuf.jl to generate Julia types directly from the `.proto` file (no external tools needed):

```julia
using ProtoBuf

# Generate Julia structs from proto file
# Arguments: proto_file, search_path, output_directory
protojl("greeter.proto", ".", "generated")
```

This creates `generated/helloworld.jl` with `HelloRequest` and `HelloReply` structs.

## Step 3: Implement Handlers

```julia
using gRPCServer
include("generated/helloworld.jl")
using .helloworld

# Unary RPC handler
function say_hello(ctx::ServerContext, request::HelloRequest)::HelloReply
    name = isempty(request.name) ? "World" : request.name
    return HelloReply(message = "Hello, $(name)!")
end

# Server streaming RPC handler
function say_hello_stream(
    ctx::ServerContext,
    request::HelloRequest,
    stream::ServerStream{HelloReply}
)::Nothing
    name = isempty(request.name) ? "World" : request.name
    for i in 1:5
        send!(stream, HelloReply(message = "Hello $(i), $(name)!"))
        sleep(0.5)  # Simulate work
    end
    return nothing
end
```

## Step 4: Create Service Descriptor

```julia
struct GreeterService end

function gRPCServer.service_descriptor(::GreeterService)
    ServiceDescriptor(
        "helloworld.Greeter",
        Dict(
            "SayHello" => MethodDescriptor(
                "SayHello",
                MethodType.UNARY,
                "helloworld.HelloRequest",
                "helloworld.HelloReply",
                say_hello
            ),
            "SayHelloStream" => MethodDescriptor(
                "SayHelloStream",
                MethodType.SERVER_STREAMING,
                "helloworld.HelloRequest",
                "helloworld.HelloReply",
                say_hello_stream
            )
        ),
        nothing  # File descriptor for reflection (optional)
    )
end
```

## Step 5: Create and Run Server

```julia
# Create server
server = GRPCServer("0.0.0.0", 50051)

# Register service
register!(server, GreeterService())

# Start server (blocking)
@info "Starting gRPC server on port 50051..."
run(server)
```

## Complete Example

Save as `server.jl`:

```julia
using gRPCServer

# Include generated types
include("generated/helloworld.jl")
using .helloworld

# Handlers
function say_hello(ctx::ServerContext, request::HelloRequest)::HelloReply
    @info "Received request" name=request.name request_id=ctx.request_id
    HelloReply(message = "Hello, $(request.name)!")
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
        send!(stream, HelloReply(message = "Hello $(i), $(request.name)!"))
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
                "helloworld.HelloRequest", "helloworld.HelloReply",
                say_hello
            ),
            "SayHelloStream" => MethodDescriptor(
                "SayHelloStream", MethodType.SERVER_STREAMING,
                "helloworld.HelloRequest", "helloworld.HelloReply",
                say_hello_stream
            )
        ),
        nothing
    )
end

# Run server
function main()
    server = GRPCServer("0.0.0.0", 50051;
        enable_health_check = true,
        enable_reflection = true
    )

    register!(server, GreeterService())

    @info "gRPC server starting" host="0.0.0.0" port=50051
    run(server)
end

main()
```

Run with:
```bash
julia server.jl
```

## Testing with grpcurl

```bash
# List services (requires reflection enabled)
grpcurl -plaintext localhost:50051 list

# Call unary RPC
grpcurl -plaintext -d '{"name": "Julia"}' \
  localhost:50051 helloworld.Greeter/SayHello

# Call streaming RPC
grpcurl -plaintext -d '{"name": "Julia"}' \
  localhost:50051 helloworld.Greeter/SayHelloStream
```

## Testing with gRPCClient.jl

```julia
using gRPCClient
include("generated/helloworld.jl")
using .helloworld

# Create channel
channel = gRPCClient.Channel("localhost", 50051)

# Create stub
stub = GreeterStub(channel)

# Call unary RPC
response = stub.SayHello(HelloRequest(name = "Julia"))
println(response.message)  # "Hello, Julia!"

# Call streaming RPC
for reply in stub.SayHelloStream(HelloRequest(name = "Julia"))
    println(reply.message)
end
```

## Adding Interceptors

```julia
# Add built-in logging interceptor
add_interceptor!(server, LoggingInterceptor())

# Add metrics interceptor with callbacks
add_interceptor!(server, MetricsInterceptor(
    on_request = (method, size) -> increment_counter("requests"),
    on_response = (method, status, ms, size) -> record_latency(ms)
))
```

## Enabling TLS

```julia
tls_config = TLSConfig(
    cert_chain = "/path/to/server.crt",
    private_key = "/path/to/server.key",
    client_ca = nothing,  # Set for mTLS
    require_client_cert = false,
    min_version = :TLSv1_2
)

server = GRPCServer("0.0.0.0", 50051;
    tls = tls_config
)
```

## Error Handling

```julia
function my_handler(ctx::ServerContext, request)
    if !is_valid(request)
        throw(GRPCError(
            StatusCode.INVALID_ARGUMENT,
            "Request validation failed",
            []
        ))
    end

    user = find_user(request.user_id)
    if user === nothing
        throw(GRPCError(
            StatusCode.NOT_FOUND,
            "User not found: $(request.user_id)",
            []
        ))
    end

    return MyResponse(user = user)
end
```

## Graceful Shutdown

```julia
# In a separate task or signal handler
function shutdown(server::GRPCServer)
    @info "Initiating graceful shutdown..."
    stop!(server; timeout = 30.0)  # Wait up to 30s for in-flight requests
    @info "Server stopped"
end
```
