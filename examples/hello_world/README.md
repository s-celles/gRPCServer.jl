# Hello World Example

A simple gRPC server demonstrating unary and server-streaming RPC patterns.

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

### Describe the Greeter Service

```bash
grpcurl -plaintext localhost:50051 describe helloworld.Greeter
```

### Call SayHello (Unary RPC)

```bash
grpcurl -plaintext -d '{"name": "World"}' localhost:50051 helloworld.Greeter/SayHello
```

Expected output:
```json
{
  "message": "Hello, World!"
}
```

### Call SayHelloStream (Server Streaming RPC)

```bash
grpcurl -plaintext -d '{"name": "Julia"}' localhost:50051 helloworld.Greeter/SayHelloStream
```

Expected output (5 messages streamed):
```json
{
  "message": "Hello 1, Julia!"
}
{
  "message": "Hello 2, Julia!"
}
{
  "message": "Hello 3, Julia!"
}
{
  "message": "Hello 4, Julia!"
}
{
  "message": "Hello 5, Julia!"
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
