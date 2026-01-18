# Test utilities module for gRPC server integration tests
# Provides mock client functionality using raw TCP/HTTP2

module TestUtils

using Sockets
using gRPCServer

export MockGRPCClient, connect!, disconnect!, is_connected
export send_preface!, build_grpc_message, parse_grpc_message
export TestServer, create_test_server, start_test_server!, stop_test_server!
export with_test_server
export MockHTTP2Request, create_mock_stream, create_mock_headers
export build_headers_frame_payload, build_data_frame
export validate_grpc_request_headers, validate_grpc_response

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
        client.socket = Sockets.connect(client.host, client.port)
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
    message = data[6:(5 + Int(len))]
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

# =============================================================================
# Mock HTTP/2 Request Utilities for Conformance Testing
# =============================================================================

"""
    MockHTTP2Request

A mock HTTP/2 request for testing gRPC protocol conformance.
"""
struct MockHTTP2Request
    method::String
    path::String
    authority::String
    scheme::String
    content_type::Union{String, Nothing}
    te::Union{String, Nothing}
    grpc_timeout::Union{String, Nothing}
    grpc_encoding::Union{String, Nothing}
    metadata::Dict{String, String}
    body::Vector{UInt8}
end

function MockHTTP2Request(;
    method::String="POST",
    path::String="/pkg.Service/Method",
    authority::String="localhost:50051",
    scheme::String="http",
    content_type::Union{String, Nothing}="application/grpc",
    te::Union{String, Nothing}="trailers",
    grpc_timeout::Union{String, Nothing}=nothing,
    grpc_encoding::Union{String, Nothing}=nothing,
    metadata::Dict{String, String}=Dict{String, String}(),
    body::Vector{UInt8}=UInt8[]
)
    return MockHTTP2Request(method, path, authority, scheme, content_type,
                            te, grpc_timeout, grpc_encoding, metadata, body)
end

"""
    create_mock_headers(request::MockHTTP2Request) -> Vector{Tuple{String, String}}

Create HTTP/2 headers from a mock request.
"""
function create_mock_headers(request::MockHTTP2Request)::Vector{Tuple{String, String}}
    headers = Tuple{String, String}[
        (":method", request.method),
        (":path", request.path),
        (":scheme", request.scheme),
        (":authority", request.authority),
    ]

    if request.content_type !== nothing
        push!(headers, ("content-type", request.content_type))
    end

    if request.te !== nothing
        push!(headers, ("te", request.te))
    end

    if request.grpc_timeout !== nothing
        push!(headers, ("grpc-timeout", request.grpc_timeout))
    end

    if request.grpc_encoding !== nothing
        push!(headers, ("grpc-encoding", request.grpc_encoding))
    end

    for (key, value) in request.metadata
        push!(headers, (key, value))
    end

    return headers
end

"""
    create_mock_stream(request::MockHTTP2Request; stream_id::UInt32=UInt32(1)) -> HTTP2Stream

Create a mock HTTP2Stream from a mock request for testing.
"""
function create_mock_stream(request::MockHTTP2Request; stream_id::UInt32=UInt32(1))
    stream = gRPCServer.HTTP2Stream(stream_id)
    stream.request_headers = create_mock_headers(request)
    stream.headers_complete = true

    if !isempty(request.body)
        write(stream.data_buffer, request.body)
    end

    # Set stream state to OPEN (simulating headers received)
    stream.state = gRPCServer.StreamState.OPEN

    return stream
end

"""
    validate_grpc_request_headers(headers::Vector{Tuple{String, String}}) -> Tuple{Bool, String}

Validate gRPC request headers according to protocol spec.
Returns (is_valid, error_message).
"""
function validate_grpc_request_headers(headers::Vector{Tuple{String, String}})::Tuple{Bool, String}
    headers_dict = Dict{String, String}()
    for (name, value) in headers
        headers_dict[lowercase(name)] = value
    end

    # Check required pseudo-headers
    method = get(headers_dict, ":method", nothing)
    if method === nothing
        return (false, "Missing :method pseudo-header")
    end
    if method != "POST"
        return (false, "Method must be POST, got: $method")
    end

    path = get(headers_dict, ":path", nothing)
    if path === nothing
        return (false, "Missing :path pseudo-header")
    end
    if !startswith(path, "/") || count('/', path) < 2
        return (false, "Invalid path format: $path")
    end

    # Check content-type
    content_type = get(headers_dict, "content-type", nothing)
    if content_type === nothing
        return (false, "Missing content-type header")
    end
    if !startswith(lowercase(content_type), "application/grpc")
        return (false, "Invalid content-type: $content_type")
    end

    return (true, "")
end

"""
    validate_grpc_response(
        status::Int,
        content_type::Union{String, Nothing},
        grpc_status::Union{Int, Nothing},
        has_trailers::Bool
    ) -> Tuple{Bool, String}

Validate gRPC response according to protocol spec.
Returns (is_valid, error_message).
"""
function validate_grpc_response(;
    status::Int=200,
    content_type::Union{String, Nothing}=nothing,
    grpc_status::Union{Int, Nothing}=nothing,
    has_trailers::Bool=false
)::Tuple{Bool, String}
    # HTTP status must be 200
    if status != 200
        return (false, "HTTP status must be 200, got: $status")
    end

    # Content-type must be application/grpc
    if content_type !== nothing && !startswith(lowercase(content_type), "application/grpc")
        return (false, "Invalid content-type: $content_type")
    end

    # grpc-status must be present in trailers
    if grpc_status === nothing && !has_trailers
        return (false, "Missing grpc-status in trailers")
    end

    # grpc-status must be valid (0-16)
    if grpc_status !== nothing && (grpc_status < 0 || grpc_status > 16)
        return (false, "Invalid grpc-status: $grpc_status")
    end

    return (true, "")
end

"""
    build_headers_frame_payload(headers::Vector{Tuple{String, String}}) -> Vector{UInt8}

Build a simple HPACK-encoded headers payload for testing.
Uses literal header field without indexing for simplicity.
"""
function build_headers_frame_payload(headers::Vector{Tuple{String, String}})::Vector{UInt8}
    result = UInt8[]

    for (name, value) in headers
        # Literal Header Field without Indexing (RFC 7541 Section 6.2.2)
        # First byte: 0000xxxx where xxxx is the name length (with huffman bit = 0)
        push!(result, 0x00)  # Literal without indexing, new name

        # Name length (7-bit prefix)
        name_bytes = Vector{UInt8}(name)
        push!(result, UInt8(length(name_bytes)))
        append!(result, name_bytes)

        # Value length (7-bit prefix)
        value_bytes = Vector{UInt8}(value)
        push!(result, UInt8(length(value_bytes)))
        append!(result, value_bytes)
    end

    return result
end

"""
    build_data_frame(data::Vector{UInt8}; end_stream::Bool=false) -> Vector{UInt8}

Build an HTTP/2 DATA frame (without the 9-byte header).
"""
function build_data_frame(data::Vector{UInt8}; end_stream::Bool=false)::Vector{UInt8}
    # This returns just the payload; the frame header is added by the caller
    return copy(data)
end

"""
    MockResponseCollector

Collects response frames for testing.
"""
mutable struct MockResponseCollector
    headers::Vector{Tuple{String, String}}
    data::Vector{UInt8}
    trailers::Vector{Tuple{String, String}}
    http_status::Union{Int, Nothing}
    grpc_status::Union{Int, Nothing}
    grpc_message::Union{String, Nothing}
end

function MockResponseCollector()
    return MockResponseCollector(
        Tuple{String, String}[],
        UInt8[],
        Tuple{String, String}[],
        nothing,
        nothing,
        nothing
    )
end

"""
    parse_response_headers!(collector::MockResponseCollector, headers::Vector{Tuple{String, String}})

Parse response headers into the collector.
"""
function parse_response_headers!(collector::MockResponseCollector, headers::Vector{Tuple{String, String}})
    for (name, value) in headers
        name_lower = lowercase(name)
        if name_lower == ":status"
            collector.http_status = parse(Int, value)
        elseif name_lower == "grpc-status"
            collector.grpc_status = parse(Int, value)
        elseif name_lower == "grpc-message"
            collector.grpc_message = value
        end
        push!(collector.headers, (name, value))
    end
end

"""
    parse_response_trailers!(collector::MockResponseCollector, trailers::Vector{Tuple{String, String}})

Parse response trailers into the collector.
"""
function parse_response_trailers!(collector::MockResponseCollector, trailers::Vector{Tuple{String, String}})
    for (name, value) in trailers
        name_lower = lowercase(name)
        if name_lower == "grpc-status"
            collector.grpc_status = parse(Int, value)
        elseif name_lower == "grpc-message"
            collector.grpc_message = value
        end
        push!(collector.trailers, (name, value))
    end
end

end # module TestUtils
