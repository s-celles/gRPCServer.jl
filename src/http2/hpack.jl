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
Note: Huffman decoding not implemented - only supports raw strings.
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

    if huffman
        # Huffman decoding not implemented
        throw(ArgumentError("Huffman decoding not supported"))
    end

    str = String(bytes[offset:(offset + length_value - 1)])
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
        # Indexed header field (Section 6.1)
        return vcat(UInt8[0x80], encode_integer(index, 7)[2:end])
    end

    if indexing == :incremental
        # Literal header field with incremental indexing (Section 6.2.1)
        add!(encoder.dynamic_table, name, value)

        if index > 0
            # Name is indexed
            header = vcat(UInt8[0x40], encode_integer(index, 6)[2:end])
        else
            # Name is literal
            header = vcat(UInt8[0x40, 0x00])
            append!(header, encode_string(name; huffman=encoder.use_huffman)[2:end])
        end
        append!(header, encode_string(value; huffman=encoder.use_huffman))
        return header
    elseif indexing == :without
        # Literal header field without indexing (Section 6.2.2)
        if index > 0
            header = vcat(UInt8[0x00], encode_integer(index, 4)[2:end])
        else
            header = UInt8[0x00, 0x00]
            append!(header, encode_string(name; huffman=encoder.use_huffman)[2:end])
        end
        append!(header, encode_string(value; huffman=encoder.use_huffman))
        return header
    else  # :never
        # Literal header field never indexed (Section 6.2.3)
        if index > 0
            header = vcat(UInt8[0x10], encode_integer(index, 4)[2:end])
        else
            header = UInt8[0x10, 0x00]
            append!(header, encode_string(name; huffman=encoder.use_huffman)[2:end])
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
