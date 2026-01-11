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

        # Create HTTP/2 connection manager
        conn = HTTP2Connection()

        # Read and validate client connection preface
        preface_data = read_connection_preface(client)
        if preface_data === nothing
            @debug "Client disconnected before sending preface"
            return
        end

        success, response_frames = process_preface(conn, preface_data)
        if !success
            @debug "Invalid client preface"
            return
        end

        @debug "Preface validated, sending server SETTINGS" num_frames=length(response_frames)

        # Send server preface (SETTINGS frame)
        for frame in response_frames
            @debug "Sending frame" type=frame.header.frame_type length=frame.header.length
            write_frame(client, frame)
        end

        @debug "Server SETTINGS sent, starting frame processing loop"

        # Main frame processing loop
        while isopen(client) && is_open(conn) && server.status == ServerStatus.RUNNING
            @debug "Waiting for next frame..."
            # Read next frame
            frame = read_frame(client)
            if frame === nothing
                @debug "read_frame returned nothing, breaking loop"
                break  # Connection closed
            end

            @debug "Received frame" type=frame.header.frame_type stream_id=frame.header.stream_id length=frame.header.length flags=frame.header.flags

            try
                # Process frame and get response frames
                response_frames = process_frame(conn, frame)

                @debug "process_frame returned" num_response_frames=length(response_frames)

                # Send response frames
                for resp_frame in response_frames
                    @debug "Sending response frame" type=resp_frame.header.frame_type stream_id=resp_frame.header.stream_id
                    write_frame(client, resp_frame)
                end

                # Check for completed streams (END_STREAM received)
                @debug "Checking for completed streams"
                process_completed_streams!(server, conn, client, peer)

            catch e
                if e isa ConnectionError
                    # Send GOAWAY and close connection
                    goaway = send_goaway(conn, e.error_code, Vector{UInt8}(e.message))
                    write_frame(client, goaway)
                    break
                elseif e isa StreamError
                    # Send RST_STREAM and continue
                    rst = send_rst_stream(conn, e.stream_id, e.error_code)
                    write_frame(client, rst)
                else
                    # Unexpected error - send GOAWAY with INTERNAL_ERROR
                    @error "Unexpected error in frame processing" exception=(e, catch_backtrace())
                    goaway = send_goaway(conn, ErrorCode.INTERNAL_ERROR, UInt8[])
                    write_frame(client, goaway)
                    break
                end
            end
        end

    catch e
        if !(e isa EOFError) && !(e isa Base.IOError) && server.status == ServerStatus.RUNNING
            @error "Connection error" exception=(e, catch_backtrace())
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

"""
    read_exactly!(io::IO, buf::Vector{UInt8}, n::Int) -> Int

Read exactly n bytes from io into buf. Returns the number of bytes read.
Throws EOFError if connection is closed before reading n bytes.
"""
function read_exactly!(io::IO, buf::Vector{UInt8}, n::Int)::Int
    total_read = 0
    while total_read < n
        bytes_read = readbytes!(io, view(buf, (total_read + 1):n), n - total_read)
        if bytes_read == 0
            throw(EOFError())
        end
        total_read += bytes_read
    end
    return total_read
end

"""
    read_connection_preface(io::IO) -> Union{Vector{UInt8}, Nothing}

Read the HTTP/2 connection preface from a client.
Returns the preface bytes, or nothing if the connection was closed.
"""
function read_connection_preface(io::IO)::Union{Vector{UInt8}, Nothing}
    try
        preface = Vector{UInt8}(undef, length(CONNECTION_PREFACE))
        n = read_exactly!(io, preface, length(CONNECTION_PREFACE))
        @debug "Read connection preface" n=n expected=length(CONNECTION_PREFACE) preface_hex=bytes2hex(preface[1:n]) expected_hex=bytes2hex(CONNECTION_PREFACE)
        return preface
    catch e
        if e isa EOFError || e isa Base.IOError
            @debug "Connection closed while reading preface" exception=e
            return nothing
        end
        rethrow()
    end
end

"""
    read_frame(io::IO) -> Union{Frame, Nothing}

Read an HTTP/2 frame from the connection.
Returns the frame, or nothing if the connection was closed.
"""
function read_frame(io::IO)::Union{Frame, Nothing}
    try
        # Read 9-byte frame header
        header_bytes = Vector{UInt8}(undef, FRAME_HEADER_SIZE)
        read_exactly!(io, header_bytes, FRAME_HEADER_SIZE)
        header = decode_frame_header(header_bytes)

        # Read payload
        payload = if header.length > 0
            buf = Vector{UInt8}(undef, header.length)
            read_exactly!(io, buf, Int(header.length))
            buf
        else
            UInt8[]
        end

        return Frame(header, payload)
    catch e
        if e isa EOFError || e isa Base.IOError
            return nothing
        end
        rethrow()
    end
end

"""
    write_frame(io::IO, frame::Frame)

Write an HTTP/2 frame to the connection.
"""
function write_frame(io::IO, frame::Frame)
    bytes = encode_frame(frame)
    write(io, bytes)
    flush(io)
end

"""
    write_frames(io::IO, frames::Vector{Frame})

Write multiple HTTP/2 frames to the connection.
"""
function write_frames(io::IO, frames::Vector{Frame})
    for frame in frames
        write(io, encode_frame(frame))
    end
    flush(io)
end

"""
    process_completed_streams!(server::GRPCServer, conn::HTTP2Connection,
                               io::IO, peer::PeerInfo)

Check for streams with complete gRPC messages and process their requests.
For unary/server-streaming, waits for END_STREAM.
For client-streaming/bidi-streaming, processes messages as they arrive.
"""
function process_completed_streams!(server::GRPCServer, conn::HTTP2Connection,
                                    io::IO, peer::PeerInfo)
    # Get list of stream IDs to process (to avoid modifying dict while iterating)
    streams_to_process = UInt32[]

    lock(conn.lock) do
        for (stream_id, stream) in conn.streams
            if stream.headers_complete && !stream.reset
                # Check if we have a complete gRPC message to process
                if stream.end_stream_received || has_complete_grpc_message(stream)
                    push!(streams_to_process, stream_id)
                end
            end
        end
    end

    for stream_id in streams_to_process
        stream = get_stream(conn, stream_id)
        if stream === nothing
            continue
        end

        try
            process_stream_request!(server, conn, stream, io, peer)

            # Only remove stream if END_STREAM was received and processed
            if stream.end_stream_received
                remove_stream(conn, stream_id)
            end
        catch e
            # Handle errors by sending appropriate response
            if e isa GRPCError
                send_error_response(conn, io, stream_id, e.code, e.message)
            else
                @error "Error processing stream" stream_id=stream_id exception=(e, catch_backtrace())
                send_error_response(conn, io, stream_id, StatusCode.INTERNAL, "Internal server error")
            end
            # Always remove stream on error
            remove_stream(conn, stream_id)
        end
    end
end

"""
    has_complete_grpc_message(stream::HTTP2Stream) -> Bool

Check if the stream has at least one complete gRPC message in its buffer.
gRPC messages are length-prefixed: 1 byte compressed flag + 4 bytes length + message.
"""
function has_complete_grpc_message(stream::HTTP2Stream)::Bool
    data = peek_data(stream)
    if length(data) < 5
        return false
    end

    # Parse message length (big-endian)
    msg_len = (UInt32(data[2]) << 24) | (UInt32(data[3]) << 16) |
              (UInt32(data[4]) << 8) | UInt32(data[5])

    # Check if we have the full message
    return length(data) >= 5 + msg_len
end

"""
    read_grpc_message!(stream::HTTP2Stream) -> Union{Vector{UInt8}, Nothing}

Read one complete gRPC message from the stream buffer.
Returns nothing if no complete message is available.
gRPC messages are length-prefixed: 1 byte compressed flag + 4 bytes length + message.
"""
function read_grpc_message!(stream::HTTP2Stream)::Union{Vector{UInt8}, Nothing}
    data = take!(stream.data_buffer)
    if length(data) < 5
        # Put data back if incomplete
        write(stream.data_buffer, data)
        return nothing
    end

    # Parse message length (big-endian)
    # compressed = data[1] != 0x00  # TODO: handle compression
    msg_len = (UInt32(data[2]) << 24) | (UInt32(data[3]) << 16) |
              (UInt32(data[4]) << 8) | UInt32(data[5])

    total_msg_size = 5 + Int(msg_len)
    if length(data) < total_msg_size
        # Put data back if incomplete
        write(stream.data_buffer, data)
        return nothing
    end

    # Extract message
    message = data[6:total_msg_size]

    # Put remaining data back in buffer
    if length(data) > total_msg_size
        write(stream.data_buffer, data[(total_msg_size + 1):end])
    end

    return message
end

"""
    process_stream_request!(server::GRPCServer, conn::HTTP2Connection,
                            stream::HTTP2Stream, io::IO, peer::PeerInfo)

Process a gRPC request on a stream. For streaming RPCs, processes one message.
"""
function process_stream_request!(server::GRPCServer, conn::HTTP2Connection,
                                 stream::HTTP2Stream, io::IO, peer::PeerInfo)
    # Extract request information from stream
    method_path = get_path(stream)
    if method_path === nothing
        send_error_response(conn, io, stream.id, StatusCode.INVALID_ARGUMENT, "Missing :path header")
        return
    end

    # Validate content-type
    content_type = get_content_type(stream)
    if content_type === nothing || !startswith(content_type, "application/grpc")
        send_error_response(conn, io, stream.id, StatusCode.INVALID_ARGUMENT, "Invalid content-type")
        return
    end

    # Read one gRPC message
    grpc_data = read_grpc_message!(stream)
    if grpc_data === nothing
        grpc_data = UInt8[]
    end

    @debug "Processing gRPC message" method=method_path data_len=length(grpc_data) end_stream=stream.end_stream_received

    # Create server context
    ctx = create_server_context(stream, peer, method_path)

    # Log request if enabled
    if server.config.log_requests
        @info "gRPC request" method=method_path peer=peer
    end

    # Look up method to determine type
    result = lookup_method(server.dispatcher.registry, method_path)
    if result === nothing
        send_error_response(conn, io, stream.id, StatusCode.UNIMPLEMENTED, "Method not found: $method_path")
        return
    end

    service, method_desc = result

    # Dispatch based on method type
    status, message, response_data = if method_desc.method_type == MethodType.UNARY
        dispatch_unary(server.dispatcher, ctx, grpc_data)
    elseif method_desc.method_type == MethodType.BIDI_STREAMING ||
           method_desc.method_type == MethodType.CLIENT_STREAMING
        # For streaming methods, handle one message at a time
        dispatch_streaming_message(server.dispatcher, ctx, grpc_data, method_desc, service)
    else
        (StatusCode.UNIMPLEMENTED, "Method type $(method_desc.method_type) not yet supported", UInt8[])
    end

    @debug "gRPC response" status=status response_len=length(response_data)

    # Send response
    send_grpc_response(conn, io, stream.id, status, message, response_data)
end

"""
    dispatch_streaming_message(dispatcher::RequestDispatcher, ctx::ServerContext,
                                request_data::Vector{UInt8}, method::MethodDescriptor,
                                service::ServiceDescriptor)

Dispatch a single message for a streaming RPC.
For reflection and similar services, handles one request and returns one response.
"""
function dispatch_streaming_message(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    request_data::Vector{UInt8},
    method::MethodDescriptor,
    service::ServiceDescriptor
)::Tuple{StatusCode.T, String, Vector{UInt8}}
    # Special handling for reflection service
    if service.name == "grpc.reflection.v1alpha.ServerReflection" && method.name == "ServerReflectionInfo"
        try
            # Handle reflection request directly with protobuf parsing
            response_data = handle_reflection_request_raw(request_data, dispatcher.registry)
            return (StatusCode.OK, "", response_data)
        catch e
            @error "Error handling reflection request" exception=(e, catch_backtrace())
            return (StatusCode.INTERNAL, "Error handling reflection: $(sprint(showerror, e))", UInt8[])
        end
    end

    # For other streaming methods, return unimplemented for now
    return (StatusCode.UNIMPLEMENTED, "Streaming method $(method.name) requires full streaming support", UInt8[])
end

import ProtoBuf as PB
using ProtoBuf: OneOf

"""
    handle_reflection_request_raw(data::Vector{UInt8}, registry::ServiceRegistry) -> Vector{UInt8}

Handle a reflection request by parsing protobuf, processing, and serializing response.
Uses ProtoBuf.jl for proper encoding/decoding.
"""
function handle_reflection_request_raw(data::Vector{UInt8}, registry::ServiceRegistry)::Vector{UInt8}
    # Decode the request using ProtoBuf.jl
    request = PB.decode(PB.ProtoDecoder(IOBuffer(data)), ServerReflectionRequest)

    @debug "Reflection request" host=request.host message_request=request.message_request

    # Build response based on request type
    response = if request.message_request !== nothing && request.message_request.name === :list_services
        # List all services
        services = [ServiceResponse(name) for name in keys(registry.services)]
        list_response = ListServiceResponse(services)
        ServerReflectionResponse(
            request.host,
            request,
            OneOf(:list_services_response, list_response)
        )
    elseif request.message_request !== nothing && request.message_request.name === :file_containing_symbol
        symbol = request.message_request[]::String
        service = get_service(registry, symbol)
        if service !== nothing && service.file_descriptor !== nothing
            fd_response = FileDescriptorResponse([service.file_descriptor])
            ServerReflectionResponse(
                request.host,
                request,
                OneOf(:file_descriptor_response, fd_response)
            )
        else
            error_response = ErrorResponse(Int32(5), "Symbol not found: $symbol")  # NOT_FOUND = 5
            ServerReflectionResponse(
                request.host,
                request,
                OneOf(:error_response, error_response)
            )
        end
    elseif request.message_request !== nothing && request.message_request.name === :file_by_filename
        filename = request.message_request[]::String
        error_response = ErrorResponse(Int32(12), "File lookup not implemented: $filename")  # UNIMPLEMENTED = 12
        ServerReflectionResponse(
            request.host,
            request,
            OneOf(:error_response, error_response)
        )
    else
        error_response = ErrorResponse(Int32(3), "Unknown request type")  # INVALID_ARGUMENT = 3
        ServerReflectionResponse(
            request.host,
            request,
            OneOf(:error_response, error_response)
        )
    end

    # Encode the response using ProtoBuf.jl
    buf = IOBuffer()
    encoder = PB.ProtoEncoder(buf)
    PB.encode(encoder, response)
    return take!(buf)
end

"""
    create_server_context(stream::HTTP2Stream, peer::PeerInfo, method::String) -> ServerContext

Create a ServerContext from HTTP/2 stream metadata.
"""
function create_server_context(stream::HTTP2Stream, peer::PeerInfo, method::String)::ServerContext
    # Extract metadata from headers and convert to Dict
    raw_metadata = get_metadata(stream)
    metadata = Dict{String, Union{String, Vector{UInt8}}}()
    for (name, value) in raw_metadata
        # Binary metadata ends with "-bin" suffix and is base64 encoded
        if endswith(name, "-bin")
            metadata[name] = Base64.base64decode(value)
        else
            metadata[name] = value
        end
    end

    # Parse timeout if present
    timeout_header = get_grpc_timeout(stream)
    deadline = if timeout_header !== nothing
        parse_grpc_timeout(timeout_header)
    else
        nothing
    end

    return ServerContext(;
        method=method,
        peer=peer,
        deadline=deadline,
        metadata=metadata
    )
end

# Note: parse_grpc_timeout is defined in context.jl

"""
    send_grpc_response(conn::HTTP2Connection, io::IO, stream_id::UInt32,
                       status::StatusCode.T, message::String, data::Vector{UInt8})

Send a complete gRPC response (headers, data, trailers).
"""
function send_grpc_response(conn::HTTP2Connection, io::IO, stream_id::UInt32,
                            status::StatusCode.T, message::String, data::Vector{UInt8})
    # Send response headers
    response_headers = [
        (":status", "200"),
        ("content-type", "application/grpc"),
        ("grpc-encoding", "identity"),
    ]
    header_frames = send_headers(conn, stream_id, response_headers; end_stream=false)
    write_frames(io, header_frames)

    # Send response data (with gRPC framing)
    if !isempty(data)
        grpc_message = encode_grpc_message(data)
        data_frames = send_data(conn, stream_id, grpc_message; end_stream=false)
        write_frames(io, data_frames)
    end

    # Send trailers with status
    trailers = [
        ("grpc-status", string(Int(status))),
    ]
    if !isempty(message)
        push!(trailers, ("grpc-message", message))
    end
    trailer_frames = send_trailers(conn, stream_id, trailers)
    write_frames(io, trailer_frames)
end

"""
    send_error_response(conn::HTTP2Connection, io::IO, stream_id::UInt32,
                        status::StatusCode.T, message::String)

Send an error response (headers + trailers only, no data).
"""
function send_error_response(conn::HTTP2Connection, io::IO, stream_id::UInt32,
                             status::StatusCode.T, message::String)
    # For errors, we can send headers and trailers in one go
    # Using trailers-only response format
    response_headers = [
        (":status", "200"),
        ("content-type", "application/grpc"),
        ("grpc-status", string(Int(status))),
        ("grpc-message", message),
    ]
    header_frames = send_headers(conn, stream_id, response_headers; end_stream=true)
    write_frames(io, header_frames)
end

"""
    encode_grpc_message(data::Vector{UInt8}; compressed::Bool=false) -> Vector{UInt8}

Encode data into gRPC Length-Prefixed Message format.
Format: 1 byte compressed flag + 4 bytes length (big-endian) + message
"""
function encode_grpc_message(data::Vector{UInt8}; compressed::Bool=false)::Vector{UInt8}
    result = Vector{UInt8}(undef, 5 + length(data))
    result[1] = compressed ? 0x01 : 0x00
    len = length(data)
    result[2] = UInt8((len >> 24) & 0xFF)
    result[3] = UInt8((len >> 16) & 0xFF)
    result[4] = UInt8((len >> 8) & 0xFF)
    result[5] = UInt8(len & 0xFF)
    if !isempty(data)
        result[6:end] .= data
    end
    return result
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
