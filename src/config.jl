# Server configuration for gRPCServer.jl

"""
    ServerStatus

Represents the lifecycle state of a gRPC server.

# States
- `STOPPED`: Server is not running
- `STARTING`: Server is binding to address
- `RUNNING`: Server is accepting connections
- `DRAINING`: Server is completing in-flight requests
- `STOPPING`: Server is releasing resources
"""
module ServerStatus
    @enum T begin
        STOPPED
        STARTING
        RUNNING
        DRAINING
        STOPPING
    end
end

"""
    TLSConfig

TLS/mTLS configuration for secure connections.

# Fields
- `cert_chain::String`: Path to server certificate chain (PEM)
- `private_key::String`: Path to server private key (PEM)
- `client_ca::Union{String, Nothing}`: Path to client CA certificate for mTLS
- `require_client_cert::Bool`: Whether to require client certificates
- `min_version::Symbol`: Minimum TLS version (`:TLSv1_2` or `:TLSv1_3`)

# Example
```julia
tls = TLSConfig(
    cert_chain = "/path/to/server.crt",
    private_key = "/path/to/server.key",
    client_ca = "/path/to/ca.crt",  # For mTLS
    require_client_cert = true,
    min_version = :TLSv1_2
)
```
"""
struct TLSConfig
    cert_chain::String
    private_key::String
    client_ca::Union{String, Nothing}
    require_client_cert::Bool
    min_version::Symbol

    function TLSConfig(;
        cert_chain::String,
        private_key::String,
        client_ca::Union{String, Nothing}=nothing,
        require_client_cert::Bool=false,
        min_version::Symbol=:TLSv1_2
    )
        if min_version ∉ (:TLSv1_2, :TLSv1_3)
            throw(ArgumentError("min_version must be :TLSv1_2 or :TLSv1_3"))
        end
        new(cert_chain, private_key, client_ca, require_client_cert, min_version)
    end
end

"""
    ServerConfig

Configuration container for gRPC server options.

# Fields

## Connection Limits
- `max_connections::Union{Int, Nothing}`: Maximum concurrent connections (nothing = unlimited)
- `max_concurrent_streams::Int`: Maximum streams per connection (default: 100)
- `max_concurrent_requests::Union{Int, Nothing}`: Maximum concurrent requests (nothing = unlimited)
- `max_queued_requests::Int`: Maximum queued requests when at capacity (default: 1000)

## Message Limits
- `max_message_size::Int`: Maximum message size in bytes (default: 4MB)

## Timeouts (in seconds)
- `keepalive_interval::Union{Float64, Nothing}`: Interval for keepalive pings (nothing = disabled)
- `keepalive_timeout::Float64`: Timeout for keepalive response (default: 20.0)
- `idle_timeout::Union{Float64, Nothing}`: Close idle connections after this time (nothing = never)
- `drain_timeout::Float64`: Maximum time to wait for graceful shutdown (default: 30.0)

## TLS
- `tls::Union{TLSConfig, Nothing}`: TLS configuration (nothing = insecure)

## Feature Toggles
- `enable_health_check::Bool`: Enable built-in health checking service (default: false)
- `enable_reflection::Bool`: Enable gRPC reflection service (default: false)
- `debug_mode::Bool`: Include exception details in error responses (default: false)
- `log_requests::Bool`: Log all incoming requests (default: false)

## Compression
- `compression_enabled::Bool`: Enable message compression (default: true)
- `compression_threshold::Int`: Minimum bytes before compression (default: 1024)
- `supported_codecs::Vector{CompressionCodec.T}`: Supported compression codecs

# Example
```julia
config = ServerConfig(
    max_message_size = 8 * 1024 * 1024,  # 8MB
    enable_health_check = true,
    enable_reflection = true,
    debug_mode = false
)
```
"""
struct ServerConfig
    # Connection limits
    max_connections::Union{Int, Nothing}
    max_concurrent_streams::Int
    max_concurrent_requests::Union{Int, Nothing}
    max_queued_requests::Int

    # Message limits
    max_message_size::Int

    # Timeouts (in seconds)
    keepalive_interval::Union{Float64, Nothing}
    keepalive_timeout::Float64
    idle_timeout::Union{Float64, Nothing}
    drain_timeout::Float64

    # TLS
    tls::Union{TLSConfig, Nothing}

    # Feature toggles
    enable_health_check::Bool
    enable_reflection::Bool
    debug_mode::Bool
    log_requests::Bool

    # Compression
    compression_enabled::Bool
    compression_threshold::Int
    supported_codecs::Vector{CompressionCodec.T}

    function ServerConfig(;
        max_connections::Union{Int, Nothing}=nothing,
        max_concurrent_streams::Int=100,
        max_concurrent_requests::Union{Int, Nothing}=nothing,
        max_queued_requests::Int=1000,
        max_message_size::Int=4 * 1024 * 1024,  # 4MB
        keepalive_interval::Union{Float64, Nothing}=nothing,
        keepalive_timeout::Float64=20.0,
        idle_timeout::Union{Float64, Nothing}=nothing,
        drain_timeout::Float64=30.0,
        tls::Union{TLSConfig, Nothing}=nothing,
        enable_health_check::Bool=false,
        enable_reflection::Bool=false,
        debug_mode::Bool=false,
        log_requests::Bool=false,
        compression_enabled::Bool=true,
        compression_threshold::Int=1024,
        supported_codecs::Vector{CompressionCodec.T}=[
            CompressionCodec.GZIP,
            CompressionCodec.DEFLATE,
            CompressionCodec.IDENTITY
        ]
    )
        # Validation
        if max_concurrent_streams < 1
            throw(ArgumentError("max_concurrent_streams must be at least 1"))
        end
        if max_message_size < 1
            throw(ArgumentError("max_message_size must be at least 1"))
        end
        if keepalive_timeout <= 0
            throw(ArgumentError("keepalive_timeout must be positive"))
        end
        if drain_timeout <= 0
            throw(ArgumentError("drain_timeout must be positive"))
        end
        if compression_threshold < 0
            throw(ArgumentError("compression_threshold must be non-negative"))
        end

        new(
            max_connections,
            max_concurrent_streams,
            max_concurrent_requests,
            max_queued_requests,
            max_message_size,
            keepalive_interval,
            keepalive_timeout,
            idle_timeout,
            drain_timeout,
            tls,
            enable_health_check,
            enable_reflection,
            debug_mode,
            log_requests,
            compression_enabled,
            compression_threshold,
            supported_codecs
        )
    end
end

function Base.show(io::IO, config::ServerConfig)
    print(io, "ServerConfig(")
    print(io, "max_message_size=", config.max_message_size)
    print(io, ", max_concurrent_streams=", config.max_concurrent_streams)
    if config.tls !== nothing
        print(io, ", tls=enabled")
    end
    if config.enable_health_check
        print(io, ", health_check=enabled")
    end
    if config.enable_reflection
        print(io, ", reflection=enabled")
    end
    print(io, ")")
end
