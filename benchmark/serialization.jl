# Message Serialization Benchmarks for gRPCServer.jl
#
# These benchmarks measure Protocol Buffer serialization performance:
# - serialize_message performance
# - deserialize_message performance
# - Different message sizes (small/medium/large)

using BenchmarkTools
using gRPCServer
using gRPCServer: serialize_message, deserialize_message, get_type_registry,
                  compress, decompress, CompressionCodec
using ProtoBuf

# Use the health check messages which are already registered
using gRPCServer: HealthCheckRequest, HealthCheckResponse

"""
    create_serialization_benchmarks() -> BenchmarkGroup

Create benchmarks for message serialization operations.
"""
function create_serialization_benchmarks()
    suite = BenchmarkGroup()

    # === Small Messages (Health Check) ===

    # Create a small message (health check request)
    # Note: ProtoBuf.jl generates positional constructors
    small_request = HealthCheckRequest("test.service")

    # Import the enum type for status
    ServingStatus = gRPCServer.var"HealthCheckResponse.ServingStatus"
    small_response = HealthCheckResponse(ServingStatus.SERVING)

    # Pre-serialize for deserialization benchmarks
    small_request_bytes = serialize_message(small_request)
    small_response_bytes = serialize_message(small_response)

    # Benchmark: Serialize small message
    suite["serialize_small"] = @benchmarkable begin
        serialize_message($small_request)
    end

    # Benchmark: Deserialize small message
    suite["deserialize_small"] = @benchmarkable begin
        deserialize_message($small_request_bytes, "grpc.health.v1.HealthCheckRequest")
    end

    # === Raw ProtoBuf Performance ===

    # Direct ProtoBuf encoding (bypassing our wrapper)
    suite["protobuf_encode_direct"] = @benchmarkable begin
        io = IOBuffer()
        encoder = ProtoBuf.ProtoEncoder(io)
        ProtoBuf.encode(encoder, $small_request)
        take!(io)
    end

    # Direct ProtoBuf decoding
    suite["protobuf_decode_direct"] = @benchmarkable begin
        io = IOBuffer($small_request_bytes)
        decoder = ProtoBuf.ProtoDecoder(io)
        ProtoBuf.decode(decoder, HealthCheckRequest)
    end

    # === Compression Performance ===

    # Test data of various sizes
    small_data = rand(UInt8, 100)
    medium_data = rand(UInt8, 4 * 1024)
    large_data = rand(UInt8, 64 * 1024)

    # Pre-compress for decompression benchmarks
    small_compressed = compress(small_data, CompressionCodec.GZIP)
    medium_compressed = compress(medium_data, CompressionCodec.GZIP)
    large_compressed = compress(large_data, CompressionCodec.GZIP)

    # Compression benchmarks
    suite["compress_small"] = @benchmarkable begin
        compress($small_data, CompressionCodec.GZIP)
    end

    suite["compress_medium"] = @benchmarkable begin
        compress($medium_data, CompressionCodec.GZIP)
    end

    suite["compress_large"] = @benchmarkable begin
        compress($large_data, CompressionCodec.GZIP)
    end

    # Decompression benchmarks
    suite["decompress_small"] = @benchmarkable begin
        decompress($small_compressed, CompressionCodec.GZIP)
    end

    suite["decompress_medium"] = @benchmarkable begin
        decompress($medium_compressed, CompressionCodec.GZIP)
    end

    suite["decompress_large"] = @benchmarkable begin
        decompress($large_compressed, CompressionCodec.GZIP)
    end

    # === Type Registry Lookup ===

    suite["type_registry_lookup"] = @benchmarkable begin
        registry = get_type_registry()
        get(registry, "grpc.health.v1.HealthCheckRequest", nothing)
    end

    # === IOBuffer Operations ===

    # These are foundational to all serialization
    suite["iobuffer_create_write_take"] = @benchmarkable begin
        io = IOBuffer()
        write(io, $small_data)
        take!(io)
    end

    suite["iobuffer_create_read"] = @benchmarkable begin
        io = IOBuffer($small_data)
        read(io)
    end

    return suite
end
