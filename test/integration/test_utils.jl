# Test utilities for gRPC server integration tests
# Provides mock client functionality using raw TCP/HTTP2

using Sockets
using gRPCServer

"""
    MockGRPCClient

A simple mock gRPC client for integration testing.
Uses raw TCP connections to communicate with the server.
"""
mutable struct MockGRPCClient
    host::String
    port::Int
    socket::Union{TCPSocket, Nothing}
    connected::Bool
end

MockGRPCClient(host::String, port::Int) = MockGRPCClient(host, port, nothing, false)

"""
    connect!(client::MockGRPCClient)

Connect to the gRPC server.
"""
function connect!(client::MockGRPCClient)
    try
        client.socket = connect(client.host, client.port)
        client.connected = true
        return true
    catch e
        client.connected = false
        return false
    end
end

"""
    disconnect!(client::MockGRPCClient)

Disconnect from the server.
"""
function disconnect!(client::MockGRPCClient)
    if client.socket !== nothing
        try
            close(client.socket)
        catch
        end
        client.socket = nothing
    end
    client.connected = false
end

"""
    is_connected(client::MockGRPCClient) -> Bool

Check if the client is connected.
"""
is_connected(client::MockGRPCClient) = client.connected && client.socket !== nothing

"""
    send_preface!(client::MockGRPCClient)

Send the HTTP/2 connection preface.
"""
function send_preface!(client::MockGRPCClient)
    if !is_connected(client)
        error("Client not connected")
    end
    # HTTP/2 connection preface
    preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
    write(client.socket, preface)
    return true
end

"""
    build_grpc_message(data::Vector{UInt8}; compressed::Bool=false) -> Vector{UInt8}

Build a gRPC Length-Prefixed Message.
Format: 1 byte compressed flag + 4 bytes length + message
"""
function build_grpc_message(data::Vector{UInt8}; compressed::Bool=false)
    result = Vector{UInt8}(undef, 5 + length(data))
    result[1] = compressed ? 0x01 : 0x00
    len = length(data)
    result[2] = UInt8((len >> 24) & 0xFF)
    result[3] = UInt8((len >> 16) & 0xFF)
    result[4] = UInt8((len >> 8) & 0xFF)
    result[5] = UInt8(len & 0xFF)
    result[6:end] .= data
    return result
end

"""
    parse_grpc_message(data::Vector{UInt8}) -> Tuple{Bool, Vector{UInt8}}

Parse a gRPC Length-Prefixed Message.
Returns (compressed, message_data).
"""
function parse_grpc_message(data::Vector{UInt8})
    if length(data) < 5
        error("Message too short")
    end
    compressed = data[1] != 0x00
    len = (UInt32(data[2]) << 24) | (UInt32(data[3]) << 16) |
          (UInt32(data[4]) << 8) | UInt32(data[5])
    if length(data) < 5 + len
        error("Message truncated")
    end
    message = data[6:(5 + len)]
    return (compressed, message)
end

"""
    TestServer

Helper to manage a test server instance.
"""
mutable struct TestServer
    server::GRPCServer
    port::Int
    started::Bool
    task::Union{Task, Nothing}
end

"""
    create_test_server(; port::Int=0, kwargs...) -> TestServer

Create a test server on an available port.
If port is 0, an ephemeral port will be used.
"""
function create_test_server(; port::Int=0, kwargs...)
    # Use random port if not specified
    if port == 0
        port = rand(50100:50999)
    end
    server = GRPCServer("127.0.0.1", port; kwargs...)
    return TestServer(server, port, false, nothing)
end

"""
    start_test_server!(ts::TestServer)

Start the test server in the background.
"""
function start_test_server!(ts::TestServer)
    ts.task = @async begin
        try
            start!(ts.server)
        catch e
            # Ignore errors during shutdown
        end
    end
    # Wait for server to start
    max_wait = 50  # 5 seconds max
    for _ in 1:max_wait
        if ts.server.status == ServerStatus.RUNNING
            ts.started = true
            return true
        end
        sleep(0.1)
    end
    return false
end

"""
    stop_test_server!(ts::TestServer)

Stop the test server.
"""
function stop_test_server!(ts::TestServer)
    if ts.started
        try
            stop!(ts.server; force=true)
        catch
        end
        ts.started = false
    end
    if ts.task !== nothing
        try
            wait(ts.task)
        catch
        end
        ts.task = nothing
    end
end

"""
    with_test_server(f::Function; kwargs...)

Run a function with a test server, ensuring cleanup.
"""
function with_test_server(f::Function; kwargs...)
    ts = create_test_server(; kwargs...)
    try
        if start_test_server!(ts)
            f(ts)
        else
            error("Failed to start test server")
        end
    finally
        stop_test_server!(ts)
    end
end

# Export test utilities
export MockGRPCClient, connect!, disconnect!, is_connected
export send_preface!, build_grpc_message, parse_grpc_message
export TestServer, create_test_server, start_test_server!, stop_test_server!
export with_test_server
