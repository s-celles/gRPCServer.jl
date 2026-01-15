# Hello World Example

A simple gRPC server demonstrating unary RPC pattern.

## Files

- `greeter.proto` - Protocol buffer service definition
- `server.jl` - Julia server implementation
- `generated/` - Auto-generated Julia types from protobuf

## Running the Server

```bash
cd examples/hello_world
julia --project=../.. server.jl
```

The server listens on port 50051 with reflection and health checking enabled.

## Testing with grpcurl

All commands below should be run from the `examples/hello_world` directory.

### List Available Services

```bash
grpcurl -plaintext localhost:50051 list
```

Expected output:
```
grpc.health.v1.Health
grpc.reflection.v1alpha.ServerReflection
helloworld.Greeter
```

### Call SayHello (Unary RPC)

```bash
grpcurl -plaintext -proto greeter.proto -d '{"name": "World"}' localhost:50051 helloworld.Greeter/SayHello
```

Expected output:
```json
{
  "message": "Hello, World!"
}
```

### Health Check

```bash
grpcurl -plaintext -d '{"service": ""}' localhost:50051 grpc.health.v1.Health/Check
```

Expected output:
```json
{
  "status": "SERVING"
}
```

## Regenerating Types

If you modify `greeter.proto`, regenerate the Julia types:

```julia
using ProtoBuf
ProtoBuf.protojl("greeter.proto", ".", "generated")
```
