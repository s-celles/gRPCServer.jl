# Unit tests for HPACK header compression
# Tests Huffman encoding/decoding, integer encoding, string encoding, and header compression

using Test
using gRPCServer

# Access internal HPACK functions through the module
# These are not exported but we can access them via the module

@testset "HPACK Unit Tests" begin

    @testset "Huffman Encoding" begin
        @testset "Basic encoding roundtrip" begin
            # Test strings that should encode well with Huffman
            test_strings = [
                "www.example.com",
                "application/grpc",
                "localhost",
                "grpc.health.v1.Health",
                "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo",
                "POST",
                "GET",
                "200",
                "content-type",
                "te",
                "trailers",
            ]

            for s in test_strings
                raw_data = Vector{UInt8}(s)
                encoded = gRPCServer.huffman_encode(raw_data)
                decoded = gRPCServer.huffman_decode(encoded)
                @test String(decoded) == s
            end
        end

        @testset "Empty string" begin
            empty = UInt8[]
            encoded = gRPCServer.huffman_encode(empty)
            @test isempty(encoded)
            decoded = gRPCServer.huffman_decode(encoded)
            @test isempty(decoded)
        end

        @testset "Single characters" begin
            for c in ['a', 'A', '0', ' ', '/', ':']
                data = Vector{UInt8}(string(c))
                encoded = gRPCServer.huffman_encode(data)
                decoded = gRPCServer.huffman_decode(encoded)
                @test String(decoded) == string(c)
            end
        end

        @testset "All printable ASCII" begin
            # Test all printable ASCII characters (32-126)
            for byte in UInt8(32):UInt8(126)
                data = [byte]
                encoded = gRPCServer.huffman_encode(data)
                decoded = gRPCServer.huffman_decode(encoded)
                @test decoded == data
            end
        end

        @testset "Space savings" begin
            # Huffman encoding should save space for typical HTTP headers
            test_cases = [
                ("www.example.com", true),      # Should save space
                ("application/grpc", true),     # Should save space
                ("localhost", true),            # Should save space
                ("POST", false),                # Short strings may not save
            ]

            for (s, should_save) in test_cases
                raw_data = Vector{UInt8}(s)
                encoded = gRPCServer.huffman_encode(raw_data)
                if should_save
                    @test length(encoded) <= length(raw_data)
                end
                # Always verify roundtrip
                decoded = gRPCServer.huffman_decode(encoded)
                @test String(decoded) == s
            end
        end
    end

    @testset "Huffman Encoded Length" begin
        @testset "Length calculation matches actual encoding" begin
            test_strings = [
                "www.example.com",
                "localhost",
                "application/grpc",
                "Hello, World!",
            ]

            for s in test_strings
                raw_data = Vector{UInt8}(s)
                predicted_len = gRPCServer.huffman_encoded_length(raw_data)
                actual_encoded = gRPCServer.huffman_encode(raw_data)
                @test predicted_len == length(actual_encoded)
            end
        end

        @testset "Empty string" begin
            @test gRPCServer.huffman_encoded_length(UInt8[]) == 0
        end
    end

    @testset "Integer Encoding" begin
        @testset "Small values (fit in prefix)" begin
            # Values less than max prefix should encode to single byte
            for prefix_bits in [5, 6, 7]
                max_prefix = (1 << prefix_bits) - 1
                for value in 0:(max_prefix - 1)
                    encoded = gRPCServer.encode_integer(value, prefix_bits)
                    @test length(encoded) == 1
                    @test encoded[1] == value
                end
            end
        end

        @testset "Large values (multi-byte encoding)" begin
            # Test values that require multi-byte encoding
            test_cases = [
                (127, 7),   # Exactly at 7-bit max
                (128, 7),   # Just over 7-bit max
                (255, 7),
                (1000, 7),
                (16383, 6),
            ]

            for (value, prefix_bits) in test_cases
                encoded = gRPCServer.encode_integer(value, prefix_bits)
                decoded, offset = gRPCServer.decode_integer(encoded, 1, prefix_bits)
                @test decoded == value
                @test offset == length(encoded) + 1
            end
        end

        @testset "Roundtrip for various prefix sizes" begin
            for prefix_bits in [4, 5, 6, 7]
                for value in [0, 1, 10, 100, 1000, 10000]
                    encoded = gRPCServer.encode_integer(value, prefix_bits)
                    decoded, _ = gRPCServer.decode_integer(encoded, 1, prefix_bits)
                    @test decoded == value
                end
            end
        end
    end

    @testset "String Encoding" begin
        @testset "Raw encoding (no Huffman)" begin
            test_strings = ["hello", "world", "test"]

            for s in test_strings
                encoded = gRPCServer.encode_string(s; huffman=false)
                # First byte should NOT have Huffman flag set
                @test (encoded[1] & 0x80) == 0
                # Decode and verify
                decoded_str, _ = gRPCServer.decode_string(encoded, 1)
                @test decoded_str == s
            end
        end

        @testset "Huffman encoding" begin
            test_strings = [
                "www.example.com",
                "localhost",
                "application/grpc",
            ]

            for s in test_strings
                encoded = gRPCServer.encode_string(s; huffman=true)
                # First byte should have Huffman flag set (if encoding saves space)
                raw_len = length(s)
                huff_encoded = gRPCServer.huffman_encode(Vector{UInt8}(s))
                if length(huff_encoded) < raw_len
                    @test (encoded[1] & 0x80) != 0
                end
                # Decode and verify
                decoded_str, _ = gRPCServer.decode_string(encoded, 1)
                @test decoded_str == s
            end
        end

        @testset "Empty string" begin
            encoded_raw = gRPCServer.encode_string(""; huffman=false)
            @test encoded_raw == UInt8[0x00]

            encoded_huff = gRPCServer.encode_string(""; huffman=true)
            @test encoded_huff == UInt8[0x00]

            decoded, _ = gRPCServer.decode_string(encoded_raw, 1)
            @test decoded == ""
        end

        @testset "Huffman auto-fallback" begin
            # Short strings where Huffman doesn't save space should fall back to raw
            short_string = "ab"
            encoded = gRPCServer.encode_string(short_string; huffman=true)
            # Decode should still work regardless
            decoded, _ = gRPCServer.decode_string(encoded, 1)
            @test decoded == short_string
        end
    end

    @testset "Dynamic Table" begin
        @testset "Basic operations" begin
            table = gRPCServer.DynamicTable(4096)
            @test isempty(table.entries)
            @test table.size == 0
            @test table.max_size == 4096

            # Add an entry
            gRPCServer.add!(table, "custom-header", "custom-value")
            @test length(table.entries) == 1
            @test table.entries[1] == ("custom-header", "custom-value")
            @test table.size == gRPCServer.entry_size("custom-header", "custom-value")
        end

        @testset "Entry eviction" begin
            # Create a small table that will require eviction
            table = gRPCServer.DynamicTable(100)

            # Add entries until we exceed capacity
            gRPCServer.add!(table, "header1", "value1")  # ~44 bytes
            gRPCServer.add!(table, "header2", "value2")  # ~44 bytes
            gRPCServer.add!(table, "header3", "value3")  # ~44 bytes - should evict header1

            # Oldest entry should be evicted
            @test length(table.entries) <= 2
            @test table.size <= table.max_size
        end

        @testset "Resize" begin
            table = gRPCServer.DynamicTable(4096)
            gRPCServer.add!(table, "header", "value")
            old_size = table.size

            # Resize to 0 should evict all entries
            Base.resize!(table, 0)
            @test isempty(table.entries)
            @test table.size == 0
            @test table.max_size == 0
        end

        @testset "Get entry spanning static and dynamic" begin
            table = gRPCServer.DynamicTable(4096)
            gRPCServer.add!(table, "x-custom", "test")

            # Static table entries (1-61)
            @test gRPCServer.get_entry(table, 1) == (":authority", "")
            @test gRPCServer.get_entry(table, 2) == (":method", "GET")
            @test gRPCServer.get_entry(table, 3) == (":method", "POST")

            # Dynamic table entry (62+)
            @test gRPCServer.get_entry(table, 62) == ("x-custom", "test")
        end
    end

    @testset "HPACK Encoder/Decoder" begin
        @testset "Basic header encoding/decoding" begin
            encoder = gRPCServer.HPACKEncoder(4096)
            decoder = gRPCServer.HPACKDecoder(4096)

            headers = [
                (":method", "GET"),
                (":path", "/"),
                (":scheme", "http"),
                ("host", "localhost"),
            ]

            encoded = gRPCServer.encode_headers(encoder, headers)
            decoded = gRPCServer.decode_headers(decoder, encoded)

            @test length(decoded) == length(headers)
            for (orig, dec) in zip(headers, decoded)
                @test orig == dec
            end
        end

        @testset "Indexed header field" begin
            encoder = gRPCServer.HPACKEncoder(4096)
            decoder = gRPCServer.HPACKDecoder(4096)

            # :method GET is index 2 in static table
            encoded = gRPCServer.encode_header(encoder, ":method", "GET")
            # Should be a single byte with indexed representation
            @test (encoded[1] & 0x80) != 0  # Indexed header field flag

            decoded = gRPCServer.decode_headers(decoder, encoded)
            @test decoded == [(":method", "GET")]
        end

        @testset "Literal header with indexing" begin
            encoder = gRPCServer.HPACKEncoder(4096)
            decoder = gRPCServer.HPACKDecoder(4096)

            # Custom header should be added to dynamic table
            encoded = gRPCServer.encode_header(encoder, "x-custom", "value"; indexing=:incremental)
            decoded = gRPCServer.decode_headers(decoder, encoded)

            @test decoded == [("x-custom", "value")]
            @test !isempty(encoder.dynamic_table.entries)
            @test !isempty(decoder.dynamic_table.entries)
        end

        @testset "Never indexed headers" begin
            encoder = gRPCServer.HPACKEncoder(4096)
            decoder = gRPCServer.HPACKDecoder(4096)

            # Authorization should never be indexed (sensitive)
            headers = [("authorization", "Bearer token123")]
            encoded = gRPCServer.encode_headers(encoder, headers)
            decoded = gRPCServer.decode_headers(decoder, encoded)

            @test decoded == headers
            # Should not be in dynamic table due to :never indexing
        end

        @testset "Huffman encoding in headers" begin
            encoder = gRPCServer.HPACKEncoder(4096; use_huffman=true)
            decoder = gRPCServer.HPACKDecoder(4096)

            headers = [
                (":path", "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo"),
                ("content-type", "application/grpc"),
            ]

            encoded = gRPCServer.encode_headers(encoder, headers)
            decoded = gRPCServer.decode_headers(decoder, encoded)

            @test decoded == headers
        end

        @testset "Multiple requests maintain state" begin
            encoder = gRPCServer.HPACKEncoder(4096)
            decoder = gRPCServer.HPACKDecoder(4096)

            # First request
            headers1 = [("x-request-id", "req-001"), (":method", "POST")]
            encoded1 = gRPCServer.encode_headers(encoder, headers1)
            decoded1 = gRPCServer.decode_headers(decoder, encoded1)
            @test decoded1 == headers1

            # Second request with same custom header should use index
            headers2 = [("x-request-id", "req-002"), (":method", "POST")]
            encoded2 = gRPCServer.encode_headers(encoder, headers2)
            decoded2 = gRPCServer.decode_headers(decoder, encoded2)
            @test decoded2 == headers2
        end
    end

    @testset "Entry Size Calculation" begin
        # Per RFC 7541 Section 4.1: size = name_len + value_len + 32
        @test gRPCServer.entry_size("name", "value") == 4 + 5 + 32
        @test gRPCServer.entry_size("", "") == 0 + 0 + 32
        @test gRPCServer.entry_size("content-type", "application/grpc") == 12 + 16 + 32
    end

    @testset "Static Table Lookup" begin
        table = gRPCServer.DynamicTable(4096)

        # Exact match in static table
        index, exact = gRPCServer.find_index(table, ":method", "GET")
        @test index == 2
        @test exact == true

        # Name-only match in static table
        index, exact = gRPCServer.find_index(table, ":method", "OPTIONS")
        @test index > 0  # Should find :method
        @test exact == false

        # Not in table
        index, exact = gRPCServer.find_index(table, "x-nonexistent", "value")
        @test index == 0
        @test exact == false
    end
end
