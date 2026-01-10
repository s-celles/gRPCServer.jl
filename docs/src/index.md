# gRPCServer.jl

A native Julia implementation of a gRPC server.

## Overview

gRPCServer.jl provides a complete gRPC server implementation in Julia, enabling you to build high-performance gRPC services. It supports all four RPC patterns, interceptors, health checking, and more.

## Features

- **All RPC Patterns**: Unary, server streaming, client streaming, and bidirectional streaming
- **Protocol Buffer Support**: Seamless integration with ProtoBuf.jl for message serialization
- **Interceptors**: Middleware pattern for cross-cutting concerns (logging, auth, metrics)
- **Health Checking**: Standard gRPC health checking protocol (grpc.health.v1)
- **Compression**: GZIP and DEFLATE compression support
- **TLS Support**: Secure connections with TLS and mutual TLS (mTLS)
- **Reflection**: gRPC reflection service for tooling integration

## Installation

```julia
using Pkg
Pkg.add("gRPCServer")
```

## Quick Example

```julia
using gRPCServer

# Define a simple handler
function my_handler(ctx::ServerContext, request)
    return "Hello, $(request.name)!"
end

# Create server
server = GRPCServer("0.0.0.0", 50051)

# Register service
descriptor = ServiceDescriptor(
    "my.Service",
    Dict(
        "MyMethod" => MethodDescriptor(
            "MyMethod",
            MethodType.UNARY,
            "my.Request",
            "my.Response",
            my_handler
        )
    ),
    nothing
)
gRPCServer.register_service!(server.dispatcher, descriptor)

# Start server
run(server)
```

See the [Quick Start](@ref) guide for a complete walkthrough.

## Table of Contents

```@contents
Pages = ["quickstart.md", "api.md", "examples.md"]
Depth = 2
```

## License

MIT License
