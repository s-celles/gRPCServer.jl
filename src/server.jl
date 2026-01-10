# Main server implementation for gRPCServer.jl

using Sockets

"""
    HealthStatus

Service health state for the health checking service.

# Values
- `UNKNOWN`: Health status is unknown
- `SERVING`: Service is healthy and accepting requests
- `NOT_SERVING`: Service is not healthy
- `SERVICE_UNKNOWN`: Service is not registered
"""
module HealthStatus
    @enum T begin
        UNKNOWN = 0
        SERVING = 1
        NOT_SERVING = 2
        SERVICE_UNKNOWN = 3
    end
end

"""
    GRPCServer

The main gRPC server managing connections, services, and lifecycle.

# Fields
- `host::String`: Server bind address
- `port::Int`: Server port
- `config::ServerConfig`: Server configuration
- `status::ServerStatus.T`: Current lifecycle state
- `dispatcher::RequestDispatcher`: Request dispatcher
- `health_status::Dict{String, HealthStatus.T}`: Per-service health status

# Example
```julia
server = GRPCServer("0.0.0.0", 50051)
register!(server, GreeterService())
run(server)
```
"""
mutable struct GRPCServer
    host::String
    port::Int
    config::ServerConfig
    status::ServerStatus.T
    dispatcher::RequestDispatcher
    health_status::Dict{String, HealthStatus.T}

    # Internal state
    socket::Union{Sockets.TCPServer, Nothing}
    connections::Vector{Any}  # Active connections
    lock::ReentrantLock
    shutdown_event::Condition
    last_error::Union{Exception, Nothing}

    function GRPCServer(
        host::String,
        port::Int;
        max_message_size::Int=4 * 1024 * 1024,
        max_concurrent_streams::Int=100,
        max_connections::Union{Int, Nothing}=nothing,
        max_concurrent_requests::Union{Int, Nothing}=nothing,
        max_queued_requests::Int=1000,
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
        # Validate host and port
        if port < 1 || port > 65535
            throw(ArgumentError("Port must be between 1 and 65535: $port"))
        end

        config = ServerConfig(;
            max_connections=max_connections,
            max_concurrent_streams=max_concurrent_streams,
            max_concurrent_requests=max_concurrent_requests,
            max_queued_requests=max_queued_requests,
            max_message_size=max_message_size,
            keepalive_interval=keepalive_interval,
            keepalive_timeout=keepalive_timeout,
            idle_timeout=idle_timeout,
            drain_timeout=drain_timeout,
            tls=tls,
            enable_health_check=enable_health_check,
            enable_reflection=enable_reflection,
            debug_mode=debug_mode,
            log_requests=log_requests,
            compression_enabled=compression_enabled,
            compression_threshold=compression_threshold,
            supported_codecs=supported_codecs
        )

        server = new(
            host,
            port,
            config,
            ServerStatus.STOPPED,
            RequestDispatcher(; debug_mode=debug_mode),
            Dict{String, HealthStatus.T}(),
            nothing,
            [],
            ReentrantLock(),
            Condition(),
            nothing
        )

        # Add logging interceptor if requested
        if log_requests
            add_interceptor!(server, LoggingInterceptor())
        end

        return server
    end
end

"""
    register!(server::GRPCServer, service)

Register a service with the server.

The service must implement `service_descriptor(service)` to provide
its `ServiceDescriptor`.

# Arguments
- `server::GRPCServer`: The server to register with
- `service`: A service implementation

# Throws
- `InvalidServerStateError`: If server is not in STOPPED state
- `ServiceAlreadyRegisteredError`: If service is already registered

# Example
```julia
server = GRPCServer("0.0.0.0", 50051)
register!(server, GreeterService())
```
"""
function register!(server::GRPCServer, service)
    if server.status != ServerStatus.STOPPED
        throw(InvalidServerStateError(:STOPPED, Symbol(server.status)))
    end

    descriptor = service_descriptor(service)
    register_service!(server.dispatcher, descriptor)

    # Initialize health status
    server.health_status[descriptor.name] = HealthStatus.SERVING

    @info "Registered service" name=descriptor.name methods=length(descriptor.methods)
end

"""
    services(server::GRPCServer) -> Vector{String}

Get a list of registered service names.

# Example
```julia
for service_name in services(server)
    println(service_name)
end
```
"""
function services(server::GRPCServer)::Vector{String}
    return list_services(server.dispatcher.registry)
end

"""
    add_interceptor!(server::GRPCServer, interceptor::Interceptor)

Add a global interceptor that applies to all services.

# Example
```julia
add_interceptor!(server, LoggingInterceptor())
add_interceptor!(server, MetricsInterceptor())
```
"""
function add_interceptor!(server::GRPCServer, interceptor::Interceptor)
    add_interceptor!(server.dispatcher, interceptor)
end

"""
    add_interceptor!(server::GRPCServer, service_name::String, interceptor::Interceptor)

Add an interceptor for a specific service.

# Example
```julia
add_interceptor!(server, "helloworld.Greeter", AuthInterceptor())
```
"""
function add_interceptor!(server::GRPCServer, service_name::String, interceptor::Interceptor)
    add_interceptor!(server.dispatcher, service_name, interceptor)
end

"""
    start!(server::GRPCServer)

Start the server and begin accepting connections.

This is a non-blocking call. Use `run(server)` for blocking operation.

# Throws
- `InvalidServerStateError`: If server is not in STOPPED state
- `BindError`: If the server cannot bind to the address

# Example
```julia
start!(server)
# Server is now running in background
```
"""
function start!(server::GRPCServer)
    if server.status != ServerStatus.STOPPED
        throw(InvalidServerStateError(:STOPPED, Symbol(server.status)))
    end

    server.status = ServerStatus.STARTING
    server.last_error = nothing

    try
        # Auto-register built-in services if enabled
        register_builtin_services!(server)

        # Parse host
        addr = if server.host == "0.0.0.0" || server.host == ""
            IPv4(0)
        elseif server.host == "::"
            IPv6(0)
        else
            try
                parse(IPv4, server.host)
            catch
                try
                    parse(IPv6, server.host)
                catch
                    # Try DNS resolution
                    getaddrinfo(server.host)
                end
            end
        end

        # Bind socket
        server.socket = listen(addr, server.port)
        server.status = ServerStatus.RUNNING

        @info "gRPC server started" host=server.host port=server.port tls=(server.config.tls !== nothing)

        # Start accept loop in background
        @async accept_loop(server)

    catch e
        server.status = ServerStatus.STOPPED
        server.last_error = e
        throw(BindError("Failed to bind to $(server.host):$(server.port)", e))
    end
end

"""
    register_builtin_services!(server::GRPCServer)

Register built-in gRPC services based on server configuration.

Registers the health checking service if `enable_health_check` is true.
Registers the reflection service if `enable_reflection` is true.
"""
function register_builtin_services!(server::GRPCServer)
    # Register health service if enabled
    if server.config.enable_health_check
        health_descriptor = create_health_service(server)
        if !haskey(server.dispatcher.registry.services, health_descriptor.name)
            register_service!(server.dispatcher, health_descriptor)
            server.health_status[""] = HealthStatus.SERVING  # Overall server health
            @debug "Registered health checking service" service=health_descriptor.name
        end
    end

    # Register reflection service if enabled
    if server.config.enable_reflection
        reflection_descriptor = create_reflection_service(server.dispatcher.registry)
        if !haskey(server.dispatcher.registry.services, reflection_descriptor.name)
            register_service!(server.dispatcher, reflection_descriptor)
            @debug "Registered reflection service" service=reflection_descriptor.name
        end
    end
end

"""
    stop!(server::GRPCServer; force::Bool=false, timeout::Float64=0.0)

Stop the server.

# Arguments
- `server::GRPCServer`: The server to stop
- `force::Bool=false`: If true, immediately close all connections
- `timeout::Float64=0.0`: Override drain timeout (0 = use config)

# Throws
- `InvalidServerStateError`: If server is not running

# Example
```julia
stop!(server)  # Graceful shutdown
stop!(server; force=true)  # Immediate shutdown
```
"""
function stop!(server::GRPCServer; force::Bool=false, timeout::Float64=0.0)
    if server.status == ServerStatus.STOPPED
        return  # Already stopped
    end

    if server.status ∉ (ServerStatus.RUNNING, ServerStatus.DRAINING)
        throw(InvalidServerStateError(:RUNNING, Symbol(server.status)))
    end

    @info "Stopping gRPC server" force=force

    if force
        # Immediate shutdown
        server.status = ServerStatus.STOPPING
        close_all_connections(server)
        if server.socket !== nothing
            close(server.socket)
            server.socket = nothing
        end
        server.status = ServerStatus.STOPPED
    else
        # Graceful shutdown
        server.status = ServerStatus.DRAINING

        # Stop accepting new connections
        if server.socket !== nothing
            close(server.socket)
            server.socket = nothing
        end

        # Wait for in-flight requests
        drain_time = timeout > 0 ? timeout : server.config.drain_timeout
        drain_deadline = time() + drain_time

        while !isempty(server.connections) && time() < drain_deadline
            sleep(0.1)
        end

        # Force close remaining connections
        server.status = ServerStatus.STOPPING
        close_all_connections(server)
        server.status = ServerStatus.STOPPED
    end

    @info "gRPC server stopped"
    lock(server.lock) do
        notify(server.shutdown_event)
    end
end

"""
    run(server::GRPCServer; block::Bool=true)

Start the server and optionally block until shutdown.

# Arguments
- `server::GRPCServer`: The server to run
- `block::Bool=true`: If true, block until server is stopped

# Example
```julia
# Blocking (typical usage)
run(server)

# Non-blocking
run(server; block=false)
# Do other things...
stop!(server)
```
"""
function Base.run(server::GRPCServer; block::Bool=true)
    start!(server)

    if block
        # Set up signal handler for graceful shutdown
        try
            lock(server.lock) do
                while server.status == ServerStatus.RUNNING
                    wait(server.shutdown_event)
                end
            end
        catch e
            if e isa InterruptException
                @info "Received interrupt signal, shutting down..."
                stop!(server)
            else
                rethrow()
            end
        end
    end
end

"""
    set_health!(server::GRPCServer, status::HealthStatus.T)

Set the health status for the overall server.

# Example
```julia
set_health!(server, HealthStatus.NOT_SERVING)  # Server entering maintenance
```
"""
function set_health!(server::GRPCServer, status::HealthStatus.T)
    server.health_status[""] = status  # Empty string = overall server health
end

"""
    set_health!(server::GRPCServer, service_name::String, status::HealthStatus.T)

Set the health status for a specific service.

# Example
```julia
set_health!(server, "helloworld.Greeter", HealthStatus.NOT_SERVING)
```
"""
function set_health!(server::GRPCServer, service_name::String, status::HealthStatus.T)
    server.health_status[service_name] = status
end

"""
    get_health(server::GRPCServer, service_name::String="") -> HealthStatus.T

Get the health status for a service (or overall server if empty string).
"""
function get_health(server::GRPCServer, service_name::String="")::HealthStatus.T
    return get(server.health_status, service_name, HealthStatus.SERVICE_UNKNOWN)
end

"""
    reload_tls!(server::GRPCServer)

Reload TLS certificates from disk.

This allows certificate rotation without server restart.

# Throws
- `InvalidServerStateError`: If server is not running
- `ArgumentError`: If TLS is not configured

# Example
```julia
reload_tls!(server)  # Reload certificates
```
"""
function reload_tls!(server::GRPCServer)
    if server.config.tls === nothing
        throw(ArgumentError("TLS is not configured"))
    end

    if server.status != ServerStatus.RUNNING
        throw(InvalidServerStateError(:RUNNING, Symbol(server.status)))
    end

    @info "Reloading TLS certificates"
    # TLS reload implementation would go here
    # This requires OpenSSL.jl integration
end

# Internal functions

function accept_loop(server::GRPCServer)
    while server.status == ServerStatus.RUNNING && server.socket !== nothing
        try
            client = accept(server.socket)
            @async handle_connection(server, client)
        catch e
            if server.status != ServerStatus.RUNNING
                break  # Expected during shutdown
            end
            @error "Error accepting connection" exception=e
        end
    end
end

function handle_connection(server::GRPCServer, client)
    lock(server.lock) do
        push!(server.connections, client)
    end

    try
        # Get peer info
        peer_addr, peer_port = getpeername(client)
        peer = PeerInfo(peer_addr, Int(peer_port))

        @debug "New connection" peer=peer

        # HTTP/2 connection handling would go here
        # For now, just a placeholder that reads/writes basic data

        # Read connection preface
        # Process HTTP/2 frames
        # Handle gRPC requests

    catch e
        if !(e isa EOFError) && server.status == ServerStatus.RUNNING
            @error "Connection error" exception=e
        end
    finally
        try
            close(client)
        catch
        end

        lock(server.lock) do
            filter!(c -> c !== client, server.connections)
        end
    end
end

function close_all_connections(server::GRPCServer)
    lock(server.lock) do
        for conn in server.connections
            try
                close(conn)
            catch
            end
        end
        empty!(server.connections)
    end
end

# Base method overloads

function Base.show(io::IO, server::GRPCServer)
    print(io, "GRPCServer($(server.host):$(server.port), status=$(server.status)")
    print(io, ", services=$(length(services(server)))")
    if server.config.tls !== nothing
        print(io, ", TLS")
    end
    print(io, ")")
end

function Base.isopen(server::GRPCServer)::Bool
    return server.status in (ServerStatus.RUNNING, ServerStatus.DRAINING)
end

"""
    status(server::GRPCServer) -> ServerStatus.T

Get the current server status.
"""
function status(server::GRPCServer)::ServerStatus.T
    return server.status
end

"""
    address(server::GRPCServer) -> String

Get the server address as "host:port".
"""
function address(server::GRPCServer)::String
    return "$(server.host):$(server.port)"
end
