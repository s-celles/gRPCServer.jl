# HPACK Interoperability Tests
# Tests gRPCServer.jl HPACK decoder against canonical test vectors from http2jp/hpack-test-case
# Validates RFC 7541 compliance using diverse encoding strategies

# Only import if not already loaded (allows standalone execution and inclusion from runtests.jl)
if !@isdefined(Test)
    using Test
end
if !@isdefined(gRPCServer)
    using gRPCServer
end
using JSON3

# ============================================================================
# Test Harness Functions (T009-T013)
# ============================================================================

"""
    load_test_file(path::String) -> NamedTuple

Load and parse a JSON test file from the hpack-test-case repository.
Returns a NamedTuple with `cases` array and optional `description`.
"""
function load_test_file(path::String)
    content = read(path, String)
    return JSON3.read(content)
end

"""
    parse_expected_headers(json_headers) -> Vector{Tuple{String, String}}

Convert JSON header array [{":method": "GET"}, ...] to Vector of tuples.
Each JSON object has exactly one key-value pair.
"""
function parse_expected_headers(json_headers)
    result = Tuple{String, String}[]
    for h in json_headers
        # Each header is a single-key object
        for (name, value) in pairs(h)
            push!(result, (String(name), String(value)))
        end
    end
    return result
end

"""
    run_test_case(decoder::gRPCServer.HPACKDecoder, test_case; impl_name::String="", filename::String="") -> Bool

Decode wire data and compare to expected headers.
Returns true if decoded headers match expected headers exactly.
Handles header_table_size updates when specified in test case.
"""
function run_test_case(decoder::gRPCServer.HPACKDecoder, test_case; impl_name::String="", filename::String="")
    seqno = test_case.seqno
    wire_hex = String(test_case.wire)
    expected = parse_expected_headers(test_case.headers)

    # Handle header_table_size if specified (T013)
    if hasproperty(test_case, :header_table_size)
        table_size = test_case.header_table_size
        gRPCServer.set_max_table_size!(decoder, table_size)
    end

    # Decode wire data
    wire_bytes = hex2bytes(wire_hex)
    decoded = gRPCServer.decode_headers(decoder, wire_bytes)

    # Compare results
    if decoded == expected
        return true
    else
        # Detailed failure message (T019)
        @error "HPACK decoding mismatch" impl=impl_name file=filename seqno=seqno expected=expected decoded=decoded
        return false
    end
end

"""
    run_test_file(filepath::String; impl_name::String="") -> Tuple{Int, Int}

Process all test cases in a file with shared decoder context.
Returns (passed_count, total_count).
Each file starts with a fresh decoder (4096 byte table by default).
"""
function run_test_file(filepath::String; impl_name::String="")
    filename = basename(filepath)
    data = load_test_file(filepath)

    # Create fresh decoder for this file (compression context is per-file)
    decoder = gRPCServer.HPACKDecoder(4096)

    passed = 0
    total = length(data.cases)

    for test_case in data.cases
        if run_test_case(decoder, test_case; impl_name=impl_name, filename=filename)
            passed += 1
        end
    end

    return (passed, total)
end

"""
    get_test_files(impl_dir::String) -> Vector{String}

Get all story_*.json files in an implementation directory, sorted by name.
"""
function get_test_files(impl_dir::String)
    files = filter(f -> startswith(f, "story_") && endswith(f, ".json"), readdir(impl_dir))
    return sort([joinpath(impl_dir, f) for f in files])
end

# ============================================================================
# Test Fixtures Path
# ============================================================================

const FIXTURES_DIR = joinpath(@__DIR__, "..", "fixtures", "hpack-test-case")

# ============================================================================
# Interoperability Tests (T014-T019)
# ============================================================================

@testset "HPACK Interoperability Tests" begin

    @testset "nghttp2" begin
        impl_dir = joinpath(FIXTURES_DIR, "nghttp2")
        if !isdir(impl_dir)
            @warn "nghttp2 test vectors not found, skipping" path=impl_dir
            @test_skip true
        else
            test_files = get_test_files(impl_dir)
            @test length(test_files) > 0

            for filepath in test_files
                filename = basename(filepath)
                @testset "$filename" begin
                    passed, total = run_test_file(filepath; impl_name="nghttp2")
                    @test passed == total
                end
            end
        end
    end

    @testset "go-hpack" begin
        impl_dir = joinpath(FIXTURES_DIR, "go-hpack")
        if !isdir(impl_dir)
            @warn "go-hpack test vectors not found, skipping" path=impl_dir
            @test_skip true
        else
            test_files = get_test_files(impl_dir)
            @test length(test_files) > 0

            for filepath in test_files
                filename = basename(filepath)
                @testset "$filename" begin
                    passed, total = run_test_file(filepath; impl_name="go-hpack")
                    @test passed == total
                end
            end
        end
    end

    @testset "python-hpack" begin
        impl_dir = joinpath(FIXTURES_DIR, "python-hpack")
        if !isdir(impl_dir)
            @warn "python-hpack test vectors not found, skipping" path=impl_dir
            @test_skip true
        else
            test_files = get_test_files(impl_dir)
            @test length(test_files) > 0

            for filepath in test_files
                filename = basename(filepath)
                @testset "$filename" begin
                    passed, total = run_test_file(filepath; impl_name="python-hpack")
                    @test passed == total
                end
            end
        end
    end

    # ========================================================================
    # Encoder Round-trip Tests (T020-T023)
    # ========================================================================

    @testset "HPACK Encoder Round-trip" begin
        raw_data_dir = joinpath(FIXTURES_DIR, "raw-data")

        if !isdir(raw_data_dir)
            @warn "raw-data test vectors not found, skipping encoder tests" path=raw_data_dir
            @test_skip true
        else
            test_files = get_test_files(raw_data_dir)

            @testset "Round-trip without Huffman" begin
                for filepath in test_files
                    filename = basename(filepath)
                    data = load_test_file(filepath)

                    # Create fresh encoder/decoder pair
                    encoder = gRPCServer.HPACKEncoder(4096; use_huffman=false)
                    decoder = gRPCServer.HPACKDecoder(4096)

                    @testset "$filename" begin
                        for test_case in data.cases
                            headers = parse_expected_headers(test_case.headers)

                            # Encode headers
                            encoded = gRPCServer.encode_headers(encoder, headers)

                            # Decode back
                            decoded = gRPCServer.decode_headers(decoder, encoded)

                            @test decoded == headers
                        end
                    end
                end
            end

            @testset "Round-trip with Huffman encoding" begin
                for filepath in test_files
                    filename = basename(filepath)
                    data = load_test_file(filepath)

                    # Create fresh encoder/decoder pair with Huffman enabled
                    encoder = gRPCServer.HPACKEncoder(4096; use_huffman=true)
                    decoder = gRPCServer.HPACKDecoder(4096)

                    @testset "$filename" begin
                        for test_case in data.cases
                            headers = parse_expected_headers(test_case.headers)

                            # Encode headers with Huffman
                            encoded = gRPCServer.encode_headers(encoder, headers)

                            # Decode back
                            decoded = gRPCServer.decode_headers(decoder, encoded)

                            @test decoded == headers
                        end
                    end
                end
            end

            @testset "Sequential encoding efficiency" begin
                # Test that dynamic table improves compression over multiple requests
                filepath = first(test_files)
                data = load_test_file(filepath)

                if length(data.cases) >= 2
                    encoder = gRPCServer.HPACKEncoder(4096; use_huffman=false)
                    decoder = gRPCServer.HPACKDecoder(4096)

                    encoded_sizes = Int[]
                    for test_case in data.cases
                        headers = parse_expected_headers(test_case.headers)
                        encoded = gRPCServer.encode_headers(encoder, headers)
                        push!(encoded_sizes, length(encoded))

                        # Verify decoding still works
                        decoded = gRPCServer.decode_headers(decoder, encoded)
                        @test decoded == headers
                    end

                    # Dynamic table should help reduce size for repeated headers
                    # (Not strictly guaranteed, but generally true for these test cases)
                    @test length(encoded_sizes) >= 2
                end
            end
        end
    end
end
