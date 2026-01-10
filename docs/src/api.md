# API Reference

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
