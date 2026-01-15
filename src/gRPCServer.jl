"""
    gRPCServer

A native Julia implementation of a gRPC server library.

gRPCServer enables Julia developers to expose services over the gRPC protocol
with support for all four RPC patterns (unary, server streaming, client streaming,
bidirectional), interceptors, health checking, reflection, TLS/mTLS, and compression.

# Quick Start

```julia
using gRPCServer

# Create server
server = GRPCServer("127.0.0.1", 50051)

# Register your service
register!(server, MyService())

# Start server
run(server)
```

See the documentation for more examples and API reference.
"""
module gRPCServer

using Base64
using Dates
using Logging
using Sockets
using UUIDs
using ProtoBuf
using CodecZlib
using TranscodingStreams
using PrecompileTools
using OpenSSL

# Include source files in dependency order

# 1. Core error types and status codes (no dependencies)
include("errors.jl")

# 2. Compression (depends on errors for potential exceptions)
include("compression.jl")

# 3. Configuration (depends on compression for CompressionCodec)
include("config.jl")

# 4. HTTP/2 implementation (internal dependencies handled by include order)
include("http2/frames.jl")
include("http2/hpack.jl")
include("http2/stream.jl")
include("http2/flow_control.jl")
include("http2/connection.jl")

# 5. Context and streams (depend on config, errors)
include("context.jl")
include("streams.jl")

# 6. Interceptors (depend on context, errors)
include("interceptors.jl")

# 7. Dispatch (depends on interceptors, context, errors)
include("dispatch.jl")

# 8. Proto definitions (needed before server.jl for reflection handling)
include("proto/grpc/health/v1/health_pb.jl")
include("proto/grpc/reflection/v1alpha/reflection_pb.jl")

# 8b. Proto descriptors (compiled .pb files for reflection service)
include("proto/descriptors.jl")

# 9. Main server (depends on everything above including proto types)
include("server.jl")

# 10. TLS implementation (optional, depends on server, config)
include("tls/config.jl")
include("tls/alpn.jl")
include("tls/reload.jl")

# 11. Built-in services (depend on server, dispatch)
include("services/health.jl")
include("services/reflection.jl")

# Core Types
export GRPCServer, ServerConfig, TLSConfig
export ServerContext, PeerInfo
export ServiceDescriptor, MethodDescriptor

# Enumerations
export ServerStatus, StatusCode, MethodType, HealthStatus, CompressionCodec

# Error Types
export GRPCError, BindError, ServiceAlreadyRegisteredError
export InvalidServerStateError, MethodSignatureError, StreamCancelledError

# Stream Types
export ServerStream, ClientStream, BidiStream

# Interceptor Types
export Interceptor, MethodInfo
export LoggingInterceptor, MetricsInterceptor, TimeoutInterceptor, RecoveryInterceptor

# Server Lifecycle
export start!, stop!
# Note: run is extended from Base, no need to export

# Service Registration
export register!, services, service_descriptor

# Interceptors
export add_interceptor!

# Health Checking
export set_health!, get_health

# TLS
export reload_tls!

# Stream Operations
export send!, close!

# Context Operations
export set_header!, set_trailer!, get_metadata, get_metadata_string, get_metadata_binary
export remaining_time, is_cancelled

# Compression functions
export compress, decompress, codec_name, parse_codec, negotiate_compression

# Proto Descriptors (for reflection service)
export HEALTH_DESCRIPTOR, REFLECTION_DESCRIPTOR
export has_health_descriptor, has_reflection_descriptor

# Precompilation workload for faster time-to-first-execution
@compile_workload begin
    # Create a server (common first operation)
    server = GRPCServer("0.0.0.0", 50051)

    # Exercise configuration paths
    _ = ServerConfig()
    _ = ServerConfig(max_message_size=8*1024*1024)

    # Exercise error types
    err = GRPCError(StatusCode.OK, "test")
    _ = sprint(show, err)

    # Exercise context creation
    ctx = ServerContext()
    _ = is_cancelled(ctx)
    _ = remaining_time(ctx)

    # Exercise compression
    data = Vector{UInt8}("Hello, gRPC!")
    compressed = compress(data, CompressionCodec.GZIP)
    _ = decompress(compressed, CompressionCodec.GZIP)
    _ = codec_name(CompressionCodec.GZIP)
    _ = parse_codec("gzip")

    # Note: ServiceDescriptor with MethodDescriptor is tested in the test suite
    # We skip it in precompile workload to avoid type registry warnings during precompilation

    # Exercise interceptor creation
    _ = LoggingInterceptor()
    _ = MetricsInterceptor()
    _ = RecoveryInterceptor()

    # Exercise health status
    set_health!(server, HealthStatus.SERVING)
    _ = get_health(server)

    # Exercise show methods
    _ = sprint(show, server)
    _ = sprint(show, ctx)
end

end # module
