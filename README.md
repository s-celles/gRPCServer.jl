# gRPCServer.jl

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/s-celles/gRPCServer.jl)
[![Build Status](https://github.com/s-celles/gRPCServer.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/s-celles/gRPCServer.jl/actions/workflows/CI.yml)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://s-celles.github.io/gRPCServer.jl/dev)

A native Julia implementation of a [gRPC](https://grpc.io/) server library.

## Features

- **All RPC Patterns**: Unary, server streaming, client streaming, and bidirectional streaming
- **Type-Safe**: Leverages Julia's type system for compile-time safety
- **High Performance**: Type-stable dispatch paths, minimal allocations
- **Production Ready**: TLS/mTLS, health checking, reflection service
- **Extensible**: Interceptor support for logging, authentication, metrics
- **Julia Idiomatic**: Iterator interfaces for streams, keyword arguments, comprehensive docstrings

## Installation

```julia
using Pkg
Pkg.add("gRPCServer")
```

## Quick Start

### 1. Define Your Service (greeter.proto)

```protobuf
syntax = "proto3";
package helloworld;

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply);
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

### 2. Generate Julia Types

```julia
using ProtoBuf
protojl("greeter.proto", ".", "generated")
```

### 3. Implement and Run Server

```julia
using gRPCServer
include("generated/helloworld.jl")
using .helloworld

# Handler function
function say_hello(ctx::ServerContext, request::HelloRequest)::HelloReply
    HelloReply(message = "Hello, $(request.name)!")
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
            )
        ),
        nothing
    )
end

# Run server
server = GRPCServer("0.0.0.0", 50051)
register!(server, GreeterService())
run(server)
```

### 4. Test with grpcurl

```bash
grpcurl -plaintext -d '{"name": "Julia"}' localhost:50051 helloworld.Greeter/SayHello
```

## Configuration

```julia
server = GRPCServer("0.0.0.0", 50051;
    max_message_size = 8 * 1024 * 1024,  # 8MB
    max_concurrent_streams = 100,
    enable_health_check = true,
    enable_reflection = true,
    debug_mode = false
)
```

## TLS Support

```julia
tls_config = TLSConfig(
    cert_chain = "/path/to/server.crt",
    private_key = "/path/to/server.key",
    client_ca = nothing,  # Set for mTLS
    require_client_cert = false,
    min_version = :TLSv1_2
)

server = GRPCServer("0.0.0.0", 50051; tls = tls_config)
```

## Interceptors

```julia
struct LoggingInterceptor <: Interceptor end

function (::LoggingInterceptor)(ctx, request, info, next)
    @info "Request" method=info.method_name request_id=ctx.request_id
    response = next(ctx, request)
    @info "Response" method=info.method_name
    return response
end

add_interceptor!(server, LoggingInterceptor())
```

## Documentation

Full documentation is available at https://s-celles.github.io/gRPCServer.jl

## Requirements

- Julia 1.10 or later
- ProtoBuf.jl for message serialization

## Related Packages

- [gRPCClient.jl](https://github.com/JuliaIO/gRPCClient.jl) - gRPC client for Julia
- [ProtoBuf.jl](https://github.com/JuliaIO/ProtoBuf.jl) - Protocol buffer support for Julia

## License

MIT License - see LICENSE file for details.
