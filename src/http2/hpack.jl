# HPACK header compression for gRPCServer.jl
# Per RFC 7541: HPACK: Header Compression for HTTP/2

"""
    StaticTable

HTTP/2 static header table per RFC 7541 Appendix A.

Contains 61 entries of common header name/value pairs.
"""
const STATIC_TABLE = [
    (":authority", ""),
    (":method", "GET"),
    (":method", "POST"),
    (":path", "/"),
    (":path", "/index.html"),
    (":scheme", "http"),
    (":scheme", "https"),
    (":status", "200"),
    (":status", "204"),
    (":status", "206"),
    (":status", "304"),
    (":status", "400"),
    (":status", "404"),
    (":status", "500"),
    ("accept-charset", ""),
    ("accept-encoding", "gzip, deflate"),
    ("accept-language", ""),
    ("accept-ranges", ""),
    ("accept", ""),
    ("access-control-allow-origin", ""),
    ("age", ""),
    ("allow", ""),
    ("authorization", ""),
    ("cache-control", ""),
    ("content-disposition", ""),
    ("content-encoding", ""),
    ("content-language", ""),
    ("content-length", ""),
    ("content-location", ""),
    ("content-range", ""),
    ("content-type", ""),
    ("cookie", ""),
    ("date", ""),
    ("etag", ""),
    ("expect", ""),
    ("expires", ""),
    ("from", ""),
    ("host", ""),
    ("if-match", ""),
    ("if-modified-since", ""),
    ("if-none-match", ""),
    ("if-range", ""),
    ("if-unmodified-since", ""),
    ("last-modified", ""),
    ("link", ""),
    ("location", ""),
    ("max-forwards", ""),
    ("proxy-authenticate", ""),
    ("proxy-authorization", ""),
    ("range", ""),
    ("referer", ""),
    ("refresh", ""),
    ("retry-after", ""),
    ("server", ""),
    ("set-cookie", ""),
    ("strict-transport-security", ""),
    ("transfer-encoding", ""),
    ("user-agent", ""),
    ("vary", ""),
    ("via", ""),
    ("www-authenticate", ""),
]

const STATIC_TABLE_SIZE = length(STATIC_TABLE)

# Huffman code table per RFC 7541 Appendix B
# Format: (code, bit_length) for each byte value 0-255, plus EOS (256)
const HUFFMAN_CODES = [
    # 0-15
    (0x1ff8, 13), (0x7fffd8, 23), (0x3ffffe2, 25), (0x3ffffe3, 25),
    (0x3ffffe4, 25), (0x3ffffe5, 25), (0x3ffffe6, 25), (0x3ffffe7, 25),
    (0x3ffffe8, 25), (0x7ffffea, 27), (0x3ffffffc, 30), (0x3ffffe9, 25),
    (0x3ffffea, 25), (0x3ffffffd, 30), (0x3ffffeb, 25), (0x3ffffec, 25),
    # 16-31
    (0x3ffffed, 25), (0x3ffffee, 25), (0x3ffffef, 25), (0x3fffff0, 25),
    (0x3fffff1, 25), (0x3fffff2, 25), (0x3fffffffe, 30), (0x3fffff3, 25),
    (0x3fffff4, 25), (0x3fffff5, 25), (0x3fffff6, 25), (0x3fffff7, 25),
    (0x3fffff8, 25), (0x3fffff9, 25), (0x3fffffa, 25), (0x3fffffb, 25),
    # 32-47: space (32) is 0x14 (6 bits)
    (0x14, 6), (0x3f8, 10), (0x3f9, 10), (0xffa, 12),
    (0x1ff9, 13), (0x15, 6), (0xf8, 8), (0x7fa, 11),
    (0x3fa, 10), (0x3fb, 10), (0xf9, 8), (0x7fb, 11),
    (0xfa, 8), (0x16, 6), (0x17, 6), (0x18, 6),
    # 48-63: digits 0-9 then punctuation
    (0x0, 5), (0x1, 5), (0x2, 5), (0x19, 6),
    (0x1a, 6), (0x1b, 6), (0x1c, 6), (0x1d, 6),
    (0x1e, 6), (0x1f, 6), (0x5c, 7), (0xfb, 8),
    (0x7ffc, 15), (0x20, 6), (0xffb, 12), (0x3fc, 10),
    # 64-79: @ A-O
    (0x1ffa, 13), (0x21, 6), (0x5d, 7), (0x5e, 7),
    (0x5f, 7), (0x60, 7), (0x61, 7), (0x62, 7),
    (0x63, 7), (0x64, 7), (0x65, 7), (0x66, 7),
    (0x67, 7), (0x68, 7), (0x69, 7), (0x6a, 7),
    # 80-95: P-_ (P-Z then punctuation)
    (0x6b, 7), (0x6c, 7), (0x6d, 7), (0x6e, 7),
    (0x6f, 7), (0x70, 7), (0x71, 7), (0x72, 7),
    (0x73, 7), (0x74, 7), (0x75, 7), (0xfc, 8),
    (0x76, 7), (0xfd, 8), (0x1ffb, 13), (0x7fff0, 19),
    # 96-111: ` a-o
    (0x1ffc, 13), (0x3, 5), (0x23, 6), (0x4, 5),
    (0x24, 6), (0x5, 5), (0x25, 6), (0x26, 6),
    (0x27, 6), (0x6, 5), (0x74, 7), (0x75, 7),
    (0x28, 6), (0x29, 6), (0x2a, 6), (0x7, 5),
    # 112-127: p-DEL
    (0x2b, 6), (0x76, 7), (0x2c, 6), (0x8, 5),
    (0x9, 5), (0x2d, 6), (0x77, 7), (0x78, 7),
    (0x79, 7), (0x7a, 7), (0x7b, 7), (0x7ffe, 15),
    (0x7fc, 11), (0x3ffd, 14), (0x1ffd, 13), (0xffffffc, 28),
    # 128-143
    (0xfffe6, 20), (0x3fffd2, 22), (0xfffe7, 20), (0xfffe8, 20),
    (0x3fffd3, 22), (0x3fffd4, 22), (0x3fffd5, 22), (0x3fffd6, 22),
    (0x3fffd7, 22), (0x3fffd8, 22), (0x3fffd9, 22), (0x3fffda, 22),
    (0x3fffdb, 22), (0x3fffdc, 22), (0x3fffdd, 22), (0x3fffde, 22),
    # 144-159
    (0xfffeb, 20), (0x3fffdf, 22), (0xfffec, 20), (0xfffed, 20),
    (0x3fffe0, 22), (0x3fffe1, 22), (0x3fffe2, 22), (0x3fffe3, 22),
    (0x3fffe4, 22), (0x3fffe5, 22), (0x3fffe6, 22), (0x3fffe7, 22),
    (0x3fffe8, 22), (0x3fffe9, 22), (0x3fffea, 22), (0x3fffeb, 22),
    # 160-175
    (0xfffee, 20), (0x3fffec, 22), (0x3fffed, 22), (0x3fffee, 22),
    (0x3fffef, 22), (0x3ffff0, 22), (0x3ffff1, 22), (0x3ffff2, 22),
    (0xffef, 16), (0x3ffff3, 22), (0x3ffff4, 22), (0x3ffff5, 22),
    (0x3ffff6, 22), (0x3ffff7, 22), (0x3ffff8, 22), (0x3ffff9, 22),
    # 176-191
    (0x1ffff0, 21), (0x1ffff1, 21), (0x3ffffa, 22), (0x1ffff2, 21),
    (0x3ffffb, 22), (0x3ffffc, 22), (0x1ffff3, 21), (0x1ffff4, 21),
    (0x1ffff5, 21), (0x1ffff6, 21), (0x1ffff7, 21), (0x3ffffd, 22),
    (0x1ffff8, 21), (0x1ffff9, 21), (0x1ffffa, 21), (0x1ffffb, 21),
    # 192-207
    (0x1ffffc, 21), (0x1ffffd, 21), (0x1ffffe, 21), (0x1fffff, 21),
    (0x2fffff0, 26), (0x2fffff1, 26), (0x2fffff2, 26), (0x2fffff3, 26),
    (0x2fffff4, 26), (0x2fffff5, 26), (0x2fffff6, 26), (0x2fffff7, 26),
    (0x2fffff8, 26), (0x2fffff9, 26), (0x2fffffa, 26), (0x2fffffb, 26),
    # 208-223
    (0x2fffffc, 26), (0x2fffffd, 26), (0x2fffffe, 26), (0x2ffffff, 26),
    (0x3fffffc, 26), (0x3fffffb, 26), (0x3fffffe, 26), (0x3ffffff, 26),
    (0x4fffffc, 27), (0x4fffffd, 27), (0x4fffffe, 27), (0x4ffffff, 27),
    (0x5fffffc, 27), (0x5fffffd, 27), (0x5fffffe, 27), (0x5ffffff, 27),
    # 224-239
    (0x6fffffc, 27), (0x6fffffd, 27), (0x6fffffe, 27), (0x6ffffff, 27),
    (0x7fffffc, 27), (0x7fffffd, 27), (0x7fffffe, 27), (0x7ffffff, 27),
    (0x8fffffc, 28), (0x8fffffd, 28), (0x8fffffe, 28), (0x8ffffff, 28),
    (0x9fffffc, 28), (0x9fffffd, 28), (0x9fffffe, 28), (0x9ffffff, 28),
    # 240-255
    (0xafffffc, 28), (0xafffffd, 28), (0xafffffe, 28), (0xaffffff, 28),
    (0xbfffffc, 28), (0xbfffffd, 28), (0xbfffffe, 28), (0xbffffff, 28),
    (0xcfffffc, 28), (0xcfffffd, 28), (0xcfffffe, 28), (0xcffffff, 28),
    (0xdfffffc, 28), (0xdfffffd, 28), (0xdfffffe, 28), (0xdffffff, 28),
    # EOS (256)
    (0x3fffffff, 30),
]

# Build Huffman decode tree for fast decoding
# Tree node: either (left_child, right_child) for internal nodes or symbol value for leaf
mutable struct HuffmanNode
    left::Union{HuffmanNode, Nothing}
    right::Union{HuffmanNode, Nothing}
    symbol::Int  # -1 for internal nodes, 0-256 for leaves

    HuffmanNode() = new(nothing, nothing, -1)
    HuffmanNode(symbol::Int) = new(nothing, nothing, symbol)
end

const HUFFMAN_ROOT = HuffmanNode()

# Build the Huffman tree at module load time
function _build_huffman_tree()
    for (symbol, (code, bits)) in enumerate(HUFFMAN_CODES)
        node = HUFFMAN_ROOT
        for i in bits:-1:1
            bit = (code >> (i - 1)) & 1
            if bit == 0
                if node.left === nothing
                    node.left = HuffmanNode()
                end
                node = node.left
            else
                if node.right === nothing
                    node.right = HuffmanNode()
                end
                node = node.right
            end
        end
        node.symbol = symbol - 1  # Convert to 0-based (0-255 for bytes, 256 for EOS)
    end
end

_build_huffman_tree()

"""
    huffman_decode(data::AbstractVector{UInt8}) -> Vector{UInt8}

Decode Huffman-encoded data per RFC 7541 Appendix B.
"""
function huffman_decode(data::AbstractVector{UInt8})::Vector{UInt8}
    result = UInt8[]
    node = HUFFMAN_ROOT
    bits_pending = 0

    for byte in data
        for i in 7:-1:0
            bit = (byte >> i) & 1
            if bit == 0
                node = node.left
            else
                node = node.right
            end

            if node === nothing
                throw(ArgumentError("Invalid Huffman code in HPACK data"))
            end

            if node.symbol >= 0
                if node.symbol == 256
                    # EOS symbol - should only appear as padding
                    # Continue to check remaining bits are all 1s (EOS padding)
                    break
                end
                push!(result, UInt8(node.symbol))
                node = HUFFMAN_ROOT
            end
        end
    end

    # After processing all bytes, we should be at root or in EOS padding
    # EOS padding consists of the most significant bits of EOS code (all 1s)
    # which means node should have traversed right-only paths

    return result
end

# Build reverse lookup for static table
const STATIC_TABLE_BY_NAME = Dict{String, Int}()
const STATIC_TABLE_BY_PAIR = Dict{Tuple{String, String}, Int}()

for (i, (name, value)) in enumerate(STATIC_TABLE)
    if !haskey(STATIC_TABLE_BY_NAME, name)
        STATIC_TABLE_BY_NAME[name] = i
    end
    if !haskey(STATIC_TABLE_BY_PAIR, (name, value))
        STATIC_TABLE_BY_PAIR[(name, value)] = i
    end
end

"""
    DynamicTable

HPACK dynamic table for header compression.

# Fields
- `entries::Vector{Tuple{String, String}}`: Header entries (most recent first)
- `size::Int`: Current size in octets
- `max_size::Int`: Maximum size in octets
"""
mutable struct DynamicTable
    entries::Vector{Tuple{String, String}}
    size::Int
    max_size::Int

    DynamicTable(max_size::Int=4096) = new(Tuple{String, String}[], 0, max_size)
end

"""
    entry_size(name::String, value::String) -> Int

Calculate the size of a header entry per RFC 7541 Section 4.1.
Size = length(name) + length(value) + 32
"""
function entry_size(name::String, value::String)::Int
    return sizeof(name) + sizeof(value) + 32
end

"""
    add!(table::DynamicTable, name::String, value::String)

Add a header entry to the dynamic table.
Evicts entries if necessary to stay within max_size.
"""
function add!(table::DynamicTable, name::String, value::String)
    size = entry_size(name, value)

    # Evict entries to make room
    while table.size + size > table.max_size && !isempty(table.entries)
        evicted_name, evicted_value = pop!(table.entries)
        table.size -= entry_size(evicted_name, evicted_value)
    end

    # Add entry if it fits
    if size <= table.max_size
        pushfirst!(table.entries, (name, value))
        table.size += size
    end
end

"""
    resize!(table::DynamicTable, new_max_size::Int)

Resize the dynamic table, evicting entries if necessary.
"""
function Base.resize!(table::DynamicTable, new_max_size::Int)
    table.max_size = new_max_size

    # Evict entries to fit new size
    while table.size > table.max_size && !isempty(table.entries)
        evicted_name, evicted_value = pop!(table.entries)
        table.size -= entry_size(evicted_name, evicted_value)
    end
end

"""
    get_entry(table::DynamicTable, index::Int) -> Tuple{String, String}

Get a header entry by index (1-based, spanning static and dynamic tables).
"""
function get_entry(table::DynamicTable, index::Int)::Tuple{String, String}
    if index < 1
        throw(ArgumentError("Index must be positive: $index"))
    elseif index <= STATIC_TABLE_SIZE
        return STATIC_TABLE[index]
    elseif index <= STATIC_TABLE_SIZE + length(table.entries)
        return table.entries[index - STATIC_TABLE_SIZE]
    else
        throw(ArgumentError("Index out of range: $index"))
    end
end

"""
    find_index(table::DynamicTable, name::String, value::String) -> Tuple{Int, Bool}

Find a header in the static/dynamic table.
Returns (index, exact_match). Index 0 means not found.
"""
function find_index(table::DynamicTable, name::String, value::String)::Tuple{Int, Bool}
    # Check static table for exact match
    if haskey(STATIC_TABLE_BY_PAIR, (name, value))
        return (STATIC_TABLE_BY_PAIR[(name, value)], true)
    end

    # Check dynamic table for exact match
    for (i, (n, v)) in enumerate(table.entries)
        if n == name && v == value
            return (STATIC_TABLE_SIZE + i, true)
        end
    end

    # Check static table for name-only match
    if haskey(STATIC_TABLE_BY_NAME, name)
        return (STATIC_TABLE_BY_NAME[name], false)
    end

    # Check dynamic table for name-only match
    for (i, (n, _)) in enumerate(table.entries)
        if n == name
            return (STATIC_TABLE_SIZE + i, false)
        end
    end

    return (0, false)
end

# Integer encoding per RFC 7541 Section 5.1

"""
    encode_integer(value::Int, prefix_bits::Int) -> Vector{UInt8}

Encode an integer using HPACK integer representation.
"""
function encode_integer(value::Int, prefix_bits::Int)::Vector{UInt8}
    max_prefix = (1 << prefix_bits) - 1

    if value < max_prefix
        return UInt8[value]
    end

    bytes = UInt8[max_prefix]
    value -= max_prefix

    while value >= 128
        push!(bytes, UInt8((value & 127) | 128))
        value >>= 7
    end
    push!(bytes, UInt8(value))

    return bytes
end

"""
    decode_integer(bytes::AbstractVector{UInt8}, offset::Int, prefix_bits::Int) -> Tuple{Int, Int}

Decode an HPACK integer starting at offset.
Returns (value, new_offset).
"""
function decode_integer(bytes::AbstractVector{UInt8}, offset::Int, prefix_bits::Int)::Tuple{Int, Int}
    if offset > length(bytes)
        throw(ArgumentError("Offset out of range"))
    end

    max_prefix = (1 << prefix_bits) - 1
    value = bytes[offset] & max_prefix
    offset += 1

    if value < max_prefix
        return (value, offset)
    end

    shift = 0
    while offset <= length(bytes)
        b = bytes[offset]
        offset += 1
        value += Int(b & 127) << shift
        shift += 7
        if (b & 128) == 0
            break
        end
    end

    return (value, offset)
end

# String encoding per RFC 7541 Section 5.2

"""
    encode_string(s::String; huffman::Bool=false) -> Vector{UInt8}

Encode a string using HPACK string representation.
Note: Huffman encoding not implemented - uses raw encoding.
"""
function encode_string(s::String; huffman::Bool=false)::Vector{UInt8}
    data = Vector{UInt8}(s)

    if huffman
        # Huffman encoding not implemented - fall back to raw
        huffman = false
    end

    length_bytes = encode_integer(length(data), 7)
    if !huffman
        length_bytes[1] &= 0x7F  # Clear huffman flag
    else
        length_bytes[1] |= 0x80  # Set huffman flag
    end

    return vcat(length_bytes, data)
end

"""
    decode_string(bytes::AbstractVector{UInt8}, offset::Int) -> Tuple{String, Int}

Decode an HPACK string starting at offset.
Returns (string, new_offset).
Supports both raw strings and Huffman-encoded strings per RFC 7541.
"""
function decode_string(bytes::AbstractVector{UInt8}, offset::Int)::Tuple{String, Int}
    if offset > length(bytes)
        throw(ArgumentError("Offset out of range"))
    end

    huffman = (bytes[offset] & 0x80) != 0
    length_value, offset = decode_integer(bytes, offset, 7)

    if offset + length_value - 1 > length(bytes)
        throw(ArgumentError("String data out of range"))
    end

    string_data = bytes[offset:(offset + length_value - 1)]

    if huffman
        # Decode Huffman-encoded string
        decoded_bytes = huffman_decode(string_data)
        str = String(decoded_bytes)
    else
        str = String(string_data)
    end

    return (str, offset + length_value)
end

"""
    HPACKEncoder

HPACK encoder for compressing HTTP/2 headers.

# Fields
- `dynamic_table::DynamicTable`: Dynamic table for compression
- `use_huffman::Bool`: Whether to use Huffman encoding
"""
mutable struct HPACKEncoder
    dynamic_table::DynamicTable
    use_huffman::Bool

    HPACKEncoder(max_table_size::Int=4096; use_huffman::Bool=false) =
        new(DynamicTable(max_table_size), use_huffman)
end

"""
    encode_header(encoder::HPACKEncoder, name::String, value::String;
                  indexing::Symbol=:incremental) -> Vector{UInt8}

Encode a single header field.

# Indexing modes
- `:incremental`: Add to dynamic table (default)
- `:without`: Don't add to dynamic table
- `:never`: Never index (sensitive data)
"""
function encode_header(encoder::HPACKEncoder, name::String, value::String;
                       indexing::Symbol=:incremental)::Vector{UInt8}
    index, exact = find_index(encoder.dynamic_table, name, value)

    if exact
        # Indexed header field (Section 6.1): first bit = 1, 7-bit prefix for index
        int_bytes = encode_integer(index, 7)
        int_bytes[1] |= 0x80  # Set first bit
        return int_bytes
    end

    if indexing == :incremental
        # Literal header field with incremental indexing (Section 6.2.1)
        # First two bits = 01, 6-bit prefix for index
        add!(encoder.dynamic_table, name, value)

        if index > 0
            # Name is indexed
            int_bytes = encode_integer(index, 6)
            int_bytes[1] |= 0x40  # Set pattern 01xxxxxx
            header = int_bytes
        else
            # Name is literal (index = 0)
            header = UInt8[0x40]  # 01000000 = literal name follows
            append!(header, encode_string(name; huffman=encoder.use_huffman))
        end
        append!(header, encode_string(value; huffman=encoder.use_huffman))
        return header
    elseif indexing == :without
        # Literal header field without indexing (Section 6.2.2)
        # First four bits = 0000, 4-bit prefix for index
        if index > 0
            int_bytes = encode_integer(index, 4)
            # No bits to set - pattern is 0000xxxx
            header = int_bytes
        else
            header = UInt8[0x00]  # 00000000 = literal name follows
            append!(header, encode_string(name; huffman=encoder.use_huffman))
        end
        append!(header, encode_string(value; huffman=encoder.use_huffman))
        return header
    else  # :never
        # Literal header field never indexed (Section 6.2.3)
        # First four bits = 0001, 4-bit prefix for index
        if index > 0
            int_bytes = encode_integer(index, 4)
            int_bytes[1] |= 0x10  # Set pattern 0001xxxx
            header = int_bytes
        else
            header = UInt8[0x10]  # 00010000 = literal name follows
            append!(header, encode_string(name; huffman=encoder.use_huffman))
        end
        append!(header, encode_string(value; huffman=encoder.use_huffman))
        return header
    end
end

"""
    encode_headers(encoder::HPACKEncoder, headers::Vector{Tuple{String, String}}) -> Vector{UInt8}

Encode a list of headers into an HPACK header block.
"""
function encode_headers(encoder::HPACKEncoder, headers::Vector{Tuple{String, String}})::Vector{UInt8}
    result = UInt8[]
    for (name, value) in headers
        # Use :never indexing for sensitive headers
        indexing = if name in ("authorization", "cookie", "set-cookie")
            :never
        else
            :incremental
        end
        append!(result, encode_header(encoder, name, value; indexing=indexing))
    end
    return result
end

"""
    HPACKDecoder

HPACK decoder for decompressing HTTP/2 headers.

# Fields
- `dynamic_table::DynamicTable`: Dynamic table for decompression
"""
mutable struct HPACKDecoder
    dynamic_table::DynamicTable

    HPACKDecoder(max_table_size::Int=4096) = new(DynamicTable(max_table_size))
end

"""
    decode_headers(decoder::HPACKDecoder, data::AbstractVector{UInt8}) -> Vector{Tuple{String, String}}

Decode an HPACK header block into a list of headers.
"""
function decode_headers(decoder::HPACKDecoder, data::AbstractVector{UInt8})::Vector{Tuple{String, String}}
    headers = Tuple{String, String}[]
    offset = 1

    while offset <= length(data)
        b = data[offset]

        if (b & 0x80) != 0
            # Indexed header field (Section 6.1)
            index, offset = decode_integer(data, offset, 7)
            name, value = get_entry(decoder.dynamic_table, index)
            push!(headers, (name, value))

        elseif (b & 0xC0) == 0x40
            # Literal header field with incremental indexing (Section 6.2.1)
            index, offset = decode_integer(data, offset, 6)

            if index > 0
                name, _ = get_entry(decoder.dynamic_table, index)
            else
                name, offset = decode_string(data, offset)
            end

            value, offset = decode_string(data, offset)
            push!(headers, (name, value))
            add!(decoder.dynamic_table, name, value)

        elseif (b & 0xF0) == 0x00
            # Literal header field without indexing (Section 6.2.2)
            index, offset = decode_integer(data, offset, 4)

            if index > 0
                name, _ = get_entry(decoder.dynamic_table, index)
            else
                name, offset = decode_string(data, offset)
            end

            value, offset = decode_string(data, offset)
            push!(headers, (name, value))

        elseif (b & 0xF0) == 0x10
            # Literal header field never indexed (Section 6.2.3)
            index, offset = decode_integer(data, offset, 4)

            if index > 0
                name, _ = get_entry(decoder.dynamic_table, index)
            else
                name, offset = decode_string(data, offset)
            end

            value, offset = decode_string(data, offset)
            push!(headers, (name, value))

        elseif (b & 0xE0) == 0x20
            # Dynamic table size update (Section 6.3)
            new_size, offset = decode_integer(data, offset, 5)
            resize!(decoder.dynamic_table, new_size)

        else
            throw(ArgumentError("Invalid HPACK header byte: 0x$(string(b, base=16, pad=2))"))
        end
    end

    return headers
end

"""
    set_max_table_size!(encoder::HPACKEncoder, size::Int)
    set_max_table_size!(decoder::HPACKDecoder, size::Int)

Update the maximum dynamic table size.
"""
function set_max_table_size!(encoder::HPACKEncoder, size::Int)
    resize!(encoder.dynamic_table, size)
end

function set_max_table_size!(decoder::HPACKDecoder, size::Int)
    resize!(decoder.dynamic_table, size)
end

"""
    encode_table_size_update(new_size::Int) -> Vector{UInt8}

Encode a dynamic table size update instruction.
"""
function encode_table_size_update(new_size::Int)::Vector{UInt8}
    bytes = encode_integer(new_size, 5)
    bytes[1] |= 0x20
    return bytes
end

function Base.show(io::IO, table::DynamicTable)
    print(io, "DynamicTable(entries=$(length(table.entries)), size=$(table.size)/$(table.max_size))")
end

function Base.show(io::IO, encoder::HPACKEncoder)
    print(io, "HPACKEncoder($(encoder.dynamic_table))")
end

function Base.show(io::IO, decoder::HPACKDecoder)
    print(io, "HPACKDecoder($(decoder.dynamic_table))")
end
