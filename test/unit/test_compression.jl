# Unit tests for compression

using Test
using gRPCServer

@testset "Compression Unit Tests" begin
    @testset "CompressionCodec Enum" begin
        @test CompressionCodec.IDENTITY isa CompressionCodec.T
        @test CompressionCodec.GZIP isa CompressionCodec.T
        @test CompressionCodec.DEFLATE isa CompressionCodec.T
    end

    @testset "codec_name" begin
        @test codec_name(CompressionCodec.IDENTITY) == "identity"
        @test codec_name(CompressionCodec.GZIP) == "gzip"
        @test codec_name(CompressionCodec.DEFLATE) == "deflate"
    end

    @testset "parse_codec" begin
        @test parse_codec("identity") == CompressionCodec.IDENTITY
        @test parse_codec("gzip") == CompressionCodec.GZIP
        @test parse_codec("deflate") == CompressionCodec.DEFLATE
        @test parse_codec("unknown") === nothing
    end

    @testset "Compress/Decompress GZIP" begin
        original = Vector{UInt8}("Hello, gRPC! This is a test message for compression.")

        # Compress
        compressed = compress(original, CompressionCodec.GZIP)
        @test length(compressed) > 0

        # Decompress
        decompressed = decompress(compressed, CompressionCodec.GZIP)
        @test decompressed == original
    end

    @testset "Compress/Decompress DEFLATE" begin
        original = Vector{UInt8}("Another test message for deflate compression.")

        # Compress
        compressed = compress(original, CompressionCodec.DEFLATE)
        @test length(compressed) > 0

        # Decompress
        decompressed = decompress(compressed, CompressionCodec.DEFLATE)
        @test decompressed == original
    end

    @testset "Identity Codec" begin
        original = Vector{UInt8}("No compression")

        # Identity should pass through unchanged
        compressed = compress(original, CompressionCodec.IDENTITY)
        @test compressed == original

        decompressed = decompress(original, CompressionCodec.IDENTITY)
        @test decompressed == original
    end

    @testset "Empty Data" begin
        empty_data = UInt8[]

        # Should handle empty data
        compressed = compress(empty_data, CompressionCodec.GZIP)
        decompressed = decompress(compressed, CompressionCodec.GZIP)
        @test decompressed == empty_data
    end

    @testset "Large Data Compression" begin
        # Create a larger dataset
        large_data = Vector{UInt8}(repeat("ABCDEFGHIJ", 1000))

        compressed = compress(large_data, CompressionCodec.GZIP)
        @test length(compressed) < length(large_data)  # Should compress well

        decompressed = decompress(compressed, CompressionCodec.GZIP)
        @test decompressed == large_data
    end
end
