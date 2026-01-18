# AC3: Message Encoding Tests
# Tests per gRPC HTTP/2 Protocol Specification
# Reference: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

using Test
using gRPCServer

# Include conformance test data
include("../fixtures/conformance_data.jl")
using .ConformanceData

@testset "AC3: Message Encoding" begin

    # =========================================================================
    # T021: Length-Prefixed Message Format
    # =========================================================================

    @testset "T021: Length-prefixed message format" begin

        @testset "Build message: 1 byte flag + 4 bytes length + data" begin
            data = UInt8[0x01, 0x02, 0x03, 0x04, 0x05]
            msg = TestUtils.build_grpc_message(data)

            # Total: 1 + 4 + 5 = 10 bytes
            @test length(msg) == 10

            # Compressed flag (byte 1)
            @test msg[1] == 0x00  # Not compressed

            # Length in big-endian (bytes 2-5)
            @test msg[2] == 0x00
            @test msg[3] == 0x00
            @test msg[4] == 0x00
            @test msg[5] == 0x05

            # Data (bytes 6-10)
            @test msg[6:10] == data
        end

        @testset "Build empty message" begin
            data = UInt8[]
            msg = TestUtils.build_grpc_message(data)

            @test length(msg) == 5  # Just header
            @test msg[1] == 0x00
            @test msg[2] == 0x00
            @test msg[3] == 0x00
            @test msg[4] == 0x00
            @test msg[5] == 0x00
        end

        @testset "Build large message (256 bytes)" begin
            data = zeros(UInt8, 256)
            msg = TestUtils.build_grpc_message(data)

            @test length(msg) == 5 + 256

            # Length = 256 = 0x00000100
            @test msg[2] == 0x00
            @test msg[3] == 0x00
            @test msg[4] == 0x01
            @test msg[5] == 0x00
        end

    end  # T021

    # =========================================================================
    # T022: Compressed Flag
    # =========================================================================

    @testset "T022: Compressed flag" begin

        @testset "Uncompressed message: flag = 0" begin
            data = UInt8[0xAA, 0xBB, 0xCC]
            msg = TestUtils.build_grpc_message(data; compressed=false)
            @test msg[1] == 0x00
        end

        @testset "Compressed message: flag = 1" begin
            data = UInt8[0xAA, 0xBB, 0xCC]
            msg = TestUtils.build_grpc_message(data; compressed=true)
            @test msg[1] == 0x01
        end

        @testset "Parse compressed flag" begin
            # Uncompressed
            msg_uncomp = UInt8[0x00, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03]
            compressed, _ = TestUtils.parse_grpc_message(msg_uncomp)
            @test !compressed

            # Compressed
            msg_comp = UInt8[0x01, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03]
            compressed, _ = TestUtils.parse_grpc_message(msg_comp)
            @test compressed
        end

    end  # T022

    # =========================================================================
    # T023: Message Length Encoding (Big-Endian)
    # =========================================================================

    @testset "T023: Message length big-endian encoding" begin

        @testset "Small message length" begin
            data = UInt8[0x01]  # 1 byte
            msg = TestUtils.build_grpc_message(data)
            # Length = 1 = 0x00000001
            @test msg[2:5] == UInt8[0x00, 0x00, 0x00, 0x01]
        end

        @testset "Medium message length (1024 bytes)" begin
            data = zeros(UInt8, 1024)
            msg = TestUtils.build_grpc_message(data)
            # Length = 1024 = 0x00000400
            @test msg[2:5] == UInt8[0x00, 0x00, 0x04, 0x00]
        end

        @testset "Large message length (65536 bytes)" begin
            data = zeros(UInt8, 65536)
            msg = TestUtils.build_grpc_message(data)
            # Length = 65536 = 0x00010000
            @test msg[2:5] == UInt8[0x00, 0x01, 0x00, 0x00]
        end

        @testset "Parse length correctly" begin
            # Message with length = 256
            msg = vcat(UInt8[0x00, 0x00, 0x00, 0x01, 0x00], zeros(UInt8, 256))
            _, data = TestUtils.parse_grpc_message(msg)
            @test length(data) == 256
        end

    end  # T023

    # =========================================================================
    # T024: Message Round-Trip
    # =========================================================================

    @testset "T024: Message encode/decode round-trip" begin

        @testset "Round-trip small message" begin
            original = UInt8[0x01, 0x02, 0x03, 0x04, 0x05]
            encoded = TestUtils.build_grpc_message(original)
            _, decoded = TestUtils.parse_grpc_message(encoded)
            @test decoded == original
        end

        @testset "Round-trip empty message" begin
            original = UInt8[]
            encoded = TestUtils.build_grpc_message(original)
            _, decoded = TestUtils.parse_grpc_message(encoded)
            @test decoded == original
        end

        @testset "Round-trip compressed flag" begin
            original = UInt8[0xAA, 0xBB]
            encoded = TestUtils.build_grpc_message(original; compressed=true)
            compressed, decoded = TestUtils.parse_grpc_message(encoded)
            @test compressed
            @test decoded == original
        end

        @testset "Round-trip binary data" begin
            original = Vector{UInt8}(0:255)
            encoded = TestUtils.build_grpc_message(original)
            _, decoded = TestUtils.parse_grpc_message(encoded)
            @test decoded == original
        end

    end  # T024

    # =========================================================================
    # T025: Invalid Message Handling
    # =========================================================================

    @testset "T025: Invalid message handling" begin

        @testset "Message too short (< 5 bytes)" begin
            @test_throws Exception TestUtils.parse_grpc_message(UInt8[0x00])
            @test_throws Exception TestUtils.parse_grpc_message(UInt8[0x00, 0x00, 0x00])
        end

        @testset "Truncated message" begin
            # Header says 5 bytes but only 2 bytes of data
            msg = UInt8[0x00, 0x00, 0x00, 0x00, 0x05, 0x01, 0x02]
            @test_throws Exception TestUtils.parse_grpc_message(msg)
        end

        @testset "Conformance test cases for invalid messages" begin
            for (input, _, _, _, should_fail) in ConformanceData.MESSAGE_FRAME_TEST_CASES
                if should_fail
                    @test_throws Exception TestUtils.parse_grpc_message(input)
                end
            end
        end

    end  # T025

    # =========================================================================
    # T026: Compression Codec Integration
    # =========================================================================

    @testset "T026: Compression codec integration" begin

        @testset "GZIP compress/decompress" begin
            original = Vector{UInt8}("Hello, gRPC compression test! " ^ 10)
            compressed = gRPCServer.compress(original, CompressionCodec.GZIP)
            decompressed = gRPCServer.decompress(compressed, CompressionCodec.GZIP)
            @test decompressed == original
            @test length(compressed) < length(original)  # Should compress
        end

        @testset "DEFLATE compress/decompress" begin
            original = Vector{UInt8}("Test data for deflate compression")
            compressed = gRPCServer.compress(original, CompressionCodec.DEFLATE)
            decompressed = gRPCServer.decompress(compressed, CompressionCodec.DEFLATE)
            @test decompressed == original
        end

        @testset "IDENTITY codec is no-op" begin
            original = UInt8[0x01, 0x02, 0x03]
            @test gRPCServer.compress(original, CompressionCodec.IDENTITY) == original
            @test gRPCServer.decompress(original, CompressionCodec.IDENTITY) == original
        end

        @testset "Parse grpc-encoding header" begin
            @test gRPCServer.parse_codec("gzip") == CompressionCodec.GZIP
            @test gRPCServer.parse_codec("deflate") == CompressionCodec.DEFLATE
            @test gRPCServer.parse_codec("identity") == CompressionCodec.IDENTITY
            @test gRPCServer.parse_codec("unknown") === nothing
        end

        @testset "Parse grpc-accept-encoding header" begin
            codecs = gRPCServer.parse_accept_encoding("gzip, deflate, identity")
            @test CompressionCodec.GZIP in codecs
            @test CompressionCodec.DEFLATE in codecs
            @test CompressionCodec.IDENTITY in codecs
        end

        @testset "Negotiate compression" begin
            client_codecs = [CompressionCodec.GZIP, CompressionCodec.DEFLATE]
            server_codecs = [CompressionCodec.DEFLATE, CompressionCodec.GZIP]
            result = gRPCServer.negotiate_compression(client_codecs, server_codecs)
            @test result == CompressionCodec.GZIP  # First match from client preference

            # No common codec
            empty_server = CompressionCodec.T[]
            result = gRPCServer.negotiate_compression(client_codecs, empty_server)
            @test result == CompressionCodec.IDENTITY  # Fallback
        end

    end  # T026

end  # AC3: Message Encoding
