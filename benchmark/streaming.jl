# Server Streaming Benchmarks for gRPCServer.jl
#
# These benchmarks measure the performance of streaming operations:
# - ServerStream send! throughput
# - Message encoding per frame

using BenchmarkTools
using gRPCServer
using gRPCServer: ServerStream, send!, serialize_message

# Mock types for benchmarking
struct MockStreamMessage
    data::Vector{UInt8}
end

"""
    create_streaming_benchmarks() -> BenchmarkGroup

Create benchmarks for streaming operations.
"""
function create_streaming_benchmarks()
    suite = BenchmarkGroup()

    # Create a mock send callback that does minimal work
    messages_sent = Ref(0)
    noop_send = (msg, compress) -> begin
        messages_sent[] += 1
        nothing
    end
    noop_close = () -> nothing

    # Small message (typical request/response)
    small_data = Vector{UInt8}("Hello, gRPC!" ^ 10)  # ~130 bytes
    small_msg = MockStreamMessage(small_data)

    # Medium message (typical data transfer)
    medium_data = rand(UInt8, 4 * 1024)  # 4 KiB
    medium_msg = MockStreamMessage(medium_data)

    # Large message (bulk transfer)
    large_data = rand(UInt8, 64 * 1024)  # 64 KiB
    large_msg = MockStreamMessage(large_data)

    # Benchmark: ServerStream creation
    suite["stream_creation"] = @benchmarkable begin
        ServerStream{MockStreamMessage}($noop_send, $noop_close)
    end

    # Benchmark: send! operation (small message)
    # Note: We can't use a fresh stream each time, so we benchmark the callback overhead
    suite["send_callback_overhead"] = @benchmarkable begin
        $noop_send($small_msg, false)
    end

    # Benchmark: Message encoding (what happens inside send!)
    # This benchmarks the serialization that would occur before sending

    # Small message encoding
    suite["encode_small"] = @benchmarkable begin
        io = IOBuffer()
        write(io, $small_data)
        take!(io)
    end

    # Medium message encoding
    suite["encode_medium"] = @benchmarkable begin
        io = IOBuffer()
        write(io, $medium_data)
        take!(io)
    end

    # Large message encoding
    suite["encode_large"] = @benchmarkable begin
        io = IOBuffer()
        write(io, $large_data)
        take!(io)
    end

    # Benchmark: gRPC message framing (5-byte header + data)
    # This measures the overhead of creating a gRPC frame
    suite["frame_creation_small"] = @benchmarkable begin
        data = $small_data
        frame = Vector{UInt8}(undef, 5 + length(data))
        frame[1] = 0x00  # Not compressed
        frame[2] = UInt8((length(data) >> 24) & 0xff)
        frame[3] = UInt8((length(data) >> 16) & 0xff)
        frame[4] = UInt8((length(data) >> 8) & 0xff)
        frame[5] = UInt8(length(data) & 0xff)
        copyto!(frame, 6, data, 1, length(data))
        frame
    end

    suite["frame_creation_large"] = @benchmarkable begin
        data = $large_data
        frame = Vector{UInt8}(undef, 5 + length(data))
        frame[1] = 0x00  # Not compressed
        frame[2] = UInt8((length(data) >> 24) & 0xff)
        frame[3] = UInt8((length(data) >> 16) & 0xff)
        frame[4] = UInt8((length(data) >> 8) & 0xff)
        frame[5] = UInt8(length(data) & 0xff)
        copyto!(frame, 6, data, 1, length(data))
        frame
    end

    return suite
end
