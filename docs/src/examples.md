# Examples

## Basic Unary RPC

A simple echo service that returns the input message:

```julia
using gRPCServer

function echo_handler(ctx::ServerContext, request)
    return request  # Echo back the request
end

server = GRPCServer("0.0.0.0", 50051)

descriptor = ServiceDescriptor(
    "example.Echo",
    Dict(
        "Echo" => MethodDescriptor(
            "Echo",
            MethodType.UNARY,
            "example.Message",
            "example.Message",
            echo_handler
        )
    ),
    nothing
)

gRPCServer.register_service!(server.dispatcher, descriptor)
run(server)
```

## Server Streaming

A service that streams multiple responses:

```julia
function stream_numbers(ctx::ServerContext, request, stream::ServerStream{NumberResponse})
    for i in 1:request.count
        if is_cancelled(ctx)
            return nothing
        end
        send!(stream, NumberResponse(value = i))
        sleep(0.1)
    end
    return nothing
end

descriptor = ServiceDescriptor(
    "example.Numbers",
    Dict(
        "StreamNumbers" => MethodDescriptor(
            "StreamNumbers",
            MethodType.SERVER_STREAMING,
            "example.CountRequest",
            "example.NumberResponse",
            stream_numbers
        )
    ),
    nothing
)
```

## Client Streaming

A service that receives multiple requests and returns a single response:

```julia
function sum_numbers(ctx::ServerContext, stream::ClientStream{NumberRequest})
    total = 0
    for request in stream
        total += request.value
    end
    return SumResponse(total = total)
end

descriptor = ServiceDescriptor(
    "example.Math",
    Dict(
        "Sum" => MethodDescriptor(
            "Sum",
            MethodType.CLIENT_STREAMING,
            "example.NumberRequest",
            "example.SumResponse",
            sum_numbers
        )
    ),
    nothing
)
```

## Bidirectional Streaming

A chat-like service with two-way streaming:

```julia
function chat(ctx::ServerContext, stream::BidiStream{ChatMessage, ChatMessage})
    for message in stream
        if is_cancelled(ctx)
            break
        end
        # Echo back with prefix
        response = ChatMessage(
            user = "Server",
            text = "You said: $(message.text)"
        )
        send!(stream, response)
    end
    close!(stream)
    return nothing
end

descriptor = ServiceDescriptor(
    "example.Chat",
    Dict(
        "Chat" => MethodDescriptor(
            "Chat",
            MethodType.BIDI_STREAMING,
            "example.ChatMessage",
            "example.ChatMessage",
            chat
        )
    ),
    nothing
)
```

## Using Interceptors

### Logging Interceptor

```julia
server = GRPCServer("0.0.0.0", 50051)

# Add logging for all requests
add_interceptor!(server, LoggingInterceptor(
    log_requests = true,
    log_responses = true,
    log_errors = true
))
```

### Metrics Interceptor

```julia
request_counter = Ref(0)
latencies = Float64[]

add_interceptor!(server, MetricsInterceptor(
    on_request = (method, size) -> begin
        request_counter[] += 1
    end,
    on_response = (method, status, duration_ms, size) -> begin
        push!(latencies, duration_ms)
    end
))
```

### Custom Authentication Interceptor

```julia
struct AuthInterceptor <: Interceptor
    valid_tokens::Set{String}
end

function (auth::AuthInterceptor)(
    ctx::ServerContext,
    request::Any,
    info::MethodInfo,
    next::Function
)
    token = get_metadata_string(ctx, "authorization")

    if token === nothing || !(token in auth.valid_tokens)
        throw(GRPCError(
            StatusCode.UNAUTHENTICATED,
            "Invalid or missing authentication token"
        ))
    end

    return next(ctx, request)
end

add_interceptor!(server, AuthInterceptor(Set(["token123", "token456"])))
```

### Rate Limiting Interceptor

```julia
mutable struct RateLimitInterceptor <: Interceptor
    requests_per_second::Int
    window_start::Float64
    request_count::Int
end

RateLimitInterceptor(rps::Int) = RateLimitInterceptor(rps, time(), 0)

function (rl::RateLimitInterceptor)(
    ctx::ServerContext,
    request::Any,
    info::MethodInfo,
    next::Function
)
    now = time()

    if now - rl.window_start >= 1.0
        rl.window_start = now
        rl.request_count = 0
    end

    rl.request_count += 1

    if rl.request_count > rl.requests_per_second
        throw(GRPCError(
            StatusCode.RESOURCE_EXHAUSTED,
            "Rate limit exceeded"
        ))
    end

    return next(ctx, request)
end

add_interceptor!(server, RateLimitInterceptor(100))
```

## Health Checking

```julia
server = GRPCServer("0.0.0.0", 50051;
    enable_health_check = true
)

# Set overall server health
set_health!(server, HealthStatus.SERVING)

# Set health for specific service
set_health!(server, "my.Service", HealthStatus.SERVING)

# Mark service as not ready (e.g., during maintenance)
set_health!(server, "my.Service", HealthStatus.NOT_SERVING)
```

## TLS Configuration

### Basic TLS

```julia
tls_config = TLSConfig(
    cert_chain = "server.crt",
    private_key = "server.key"
)

server = GRPCServer("0.0.0.0", 50051; tls = tls_config)
```

### Mutual TLS (mTLS)

```julia
tls_config = TLSConfig(
    cert_chain = "server.crt",
    private_key = "server.key",
    client_ca = "ca.crt",
    require_client_cert = true
)

server = GRPCServer("0.0.0.0", 50051; tls = tls_config)
```

### Hot Reloading Certificates

```julia
# Reload certificates without restarting server
reload_tls!(server)
```

## Error Handling

### Returning Specific Status Codes

```julia
function my_handler(ctx::ServerContext, request)
    if request.id < 0
        throw(GRPCError(
            StatusCode.INVALID_ARGUMENT,
            "ID must be non-negative"
        ))
    end

    item = find_item(request.id)
    if item === nothing
        throw(GRPCError(
            StatusCode.NOT_FOUND,
            "Item not found: $(request.id)"
        ))
    end

    if !has_permission(ctx, item)
        throw(GRPCError(
            StatusCode.PERMISSION_DENIED,
            "Access denied to item $(request.id)"
        ))
    end

    return item
end
```

### Error Details

```julia
throw(GRPCError(
    StatusCode.INVALID_ARGUMENT,
    "Multiple validation errors",
    Any[
        Dict("field" => "email", "error" => "Invalid email format"),
        Dict("field" => "age", "error" => "Must be positive")
    ]
))
```

## Context Usage

### Accessing Metadata

```julia
function my_handler(ctx::ServerContext, request)
    # Get string metadata
    auth = get_metadata_string(ctx, "authorization")

    # Get binary metadata (keys ending in -bin)
    trace = get_metadata_binary(ctx, "x-trace-bin")

    # Check remaining time before deadline
    remaining = remaining_time(ctx)
    if remaining !== nothing && remaining < 1.0
        @warn "Less than 1 second remaining"
    end

    return response
end
```

### Setting Response Headers and Trailers

```julia
function my_handler(ctx::ServerContext, request)
    # Set response header
    set_header!(ctx, "x-request-id", string(ctx.request_id))

    # Set trailer (sent at end of response)
    set_trailer!(ctx, "x-processing-time", "50ms")

    return response
end
```

## Compression

### Server-side Compression

```julia
server = GRPCServer("0.0.0.0", 50051;
    enabled_compression = [CompressionCodec.GZIP, CompressionCodec.DEFLATE]
)
```

### Manual Compression

```julia
using gRPCServer: compress, decompress, CompressionCodec

data = Vector{UInt8}("Large data to compress...")

# Compress with GZIP
compressed = compress(data, CompressionCodec.GZIP)

# Decompress
original = decompress(compressed, CompressionCodec.GZIP)
```

## Graceful Shutdown

```julia
server = GRPCServer("0.0.0.0", 50051)
register!(server, MyService())

# Run in background task
server_task = @async run(server; block = true)

# Later, initiate graceful shutdown
@info "Shutting down..."
stop!(server; timeout = 30.0)

# Wait for server to stop
wait(server_task)
@info "Server stopped"
```
