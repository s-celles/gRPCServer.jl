# API Reference

## Module

```@docs
gRPCServer
```

## Server Types

```@docs
GRPCServer
ServerConfig
TLSConfig
ServerStatus
```

## Context Types

```@docs
ServerContext
PeerInfo
```

## Service Registration

```@docs
ServiceDescriptor
MethodDescriptor
MethodType
register!
services
service_descriptor
```

## Stream Types

```@docs
ServerStream
ClientStream
BidiStream
send!
close!
```

## Error Handling

```@docs
StatusCode
GRPCError
BindError
ServiceAlreadyRegisteredError
InvalidServerStateError
MethodSignatureError
StreamCancelledError
```

## Interceptors

```@docs
Interceptor
MethodInfo
LoggingInterceptor
MetricsInterceptor
TimeoutInterceptor
RecoveryInterceptor
add_interceptor!
```

## Health Checking

```@docs
HealthStatus
set_health!
get_health
```

## Reflection Support

```@docs
HEALTH_DESCRIPTOR
REFLECTION_DESCRIPTOR
has_health_descriptor
has_reflection_descriptor
```

## Server Lifecycle

```@docs
start!
stop!
```

## TLS

```@docs
reload_tls!
```

## Context Operations

```@docs
set_header!
set_trailer!
get_metadata
get_metadata_string
get_metadata_binary
remaining_time
is_cancelled
```

## Compression

```@docs
CompressionCodec
compress
decompress
codec_name
parse_codec
negotiate_compression
```

## HTTP/2 Stream State

These functions are used for advanced stream state management, particularly for handling edge cases with client disconnection.

```@docs
can_send
StreamError
```

## Internal Types

These are internal types used by the HTTP/2 implementation. They are documented for reference but are not part of the public API.

```@docs
gRPCServer.FrameType
gRPCServer.FrameFlags
gRPCServer.ErrorCode
gRPCServer.SettingsParameter
gRPCServer.StreamState
gRPCServer.ConnectionState
```
