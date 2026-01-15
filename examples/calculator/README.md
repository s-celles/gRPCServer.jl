# Calculator Example

A gRPC server demonstrating arithmetic operations with error handling.

## Files

- `calculator.proto` - Protocol buffer service definition
- `server.jl` - Julia server implementation
- `generated/` - Auto-generated Julia types from protobuf

## Running the Server

```bash
cd examples/calculator
julia --project=../.. server.jl
```

The server listens on port 50052 with reflection and health checking enabled.

## Testing with grpcurl

### List Available Services

```bash
grpcurl -plaintext localhost:50052 list
```

Expected output:
```
calculator.Calculator
grpc.health.v1.Health
grpc.reflection.v1alpha.ServerReflection
```

### Describe the Calculator Service

```bash
grpcurl -plaintext localhost:50052 describe calculator.Calculator
```

### Add Operation

```bash
grpcurl -plaintext -d '{"first_number": 5, "second_number": 3}' localhost:50052 calculator.Calculator/Add
```

Expected output:
```json
{
  "result": 8
}
```

### Subtract Operation

```bash
grpcurl -plaintext -d '{"first_number": 10, "second_number": 4}' localhost:50052 calculator.Calculator/Subtract
```

Expected output:
```json
{
  "result": 6
}
```

### Multiply Operation

```bash
grpcurl -plaintext -d '{"first_number": 7, "second_number": 6}' localhost:50052 calculator.Calculator/Multiply
```

Expected output:
```json
{
  "result": 42
}
```

### Divide Operation

```bash
grpcurl -plaintext -d '{"first_number": 20, "second_number": 4}' localhost:50052 calculator.Calculator/Divide
```

Expected output:
```json
{
  "result": 5
}
```

### Floating-Point Division

```bash
grpcurl -plaintext -d '{"first_number": 7.5, "second_number": 2.5}' localhost:50052 calculator.Calculator/Divide
```

Expected output:
```json
{
  "result": 3
}
```

### Division by Zero (Error Handling)

```bash
grpcurl -plaintext -d '{"first_number": 10, "second_number": 0}' localhost:50052 calculator.Calculator/Divide
```

Expected output:
```
ERROR:
  Code: InvalidArgument
  Message: Division by zero
```

### Health Check

```bash
grpcurl -plaintext -d '{"service": ""}' localhost:50052 grpc.health.v1.Health/Check
```

Expected output:
```json
{
  "status": "SERVING"
}
```

## Regenerating Types

If you modify `calculator.proto`, regenerate the Julia types:

```julia
using ProtoBuf
ProtoBuf.protojl("calculator.proto", ".", "generated")
```
