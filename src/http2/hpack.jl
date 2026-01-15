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
    # 0-15 (control characters)
    (0x1ff8, 13),      # 0
    (0x7fffd8, 23),    # 1
    (0xfffffe2, 28),   # 2
    (0xfffffe3, 28),   # 3
    (0xfffffe4, 28),   # 4
    (0xfffffe5, 28),   # 5
    (0xfffffe6, 28),   # 6
    (0xfffffe7, 28),   # 7
    (0xfffffe8, 28),   # 8
    (0xffffea, 24),    # 9
    (0x3ffffffc, 30),  # 10
    (0xfffffe9, 28),   # 11
    (0xfffffea, 28),   # 12
    (0x3ffffffd, 30),  # 13
    (0xfffffeb, 28),   # 14
    (0xfffffec, 28),   # 15
    # 16-31
    (0xfffffed, 28),   # 16
    (0xfffffee, 28),   # 17
    (0xfffffef, 28),   # 18
    (0xffffff0, 28),   # 19
    (0xffffff1, 28),   # 20
    (0xffffff2, 28),   # 21
    (0x3ffffffe, 30),  # 22
    (0xffffff3, 28),   # 23
    (0xffffff4, 28),   # 24
    (0xffffff5, 28),   # 25
    (0xffffff6, 28),   # 26
    (0xffffff7, 28),   # 27
    (0xffffff8, 28),   # 28
    (0xffffff9, 28),   # 29
    (0xffffffa, 28),   # 30
    (0xffffffb, 28),   # 31
    # 32-47: space ! " # $ % & ' ( ) * + , - . /
    (0x14, 6),         # 32 (space)
    (0x3f8, 10),       # 33 !
    (0x3f9, 10),       # 34 "
    (0xffa, 12),       # 35 #
    (0x1ff9, 13),      # 36 $
    (0x15, 6),         # 37 %
    (0xf8, 8),         # 38 &
    (0x7fa, 11),       # 39 '
    (0x3fa, 10),       # 40 (
    (0x3fb, 10),       # 41 )
    (0xf9, 8),         # 42 *
    (0x7fb, 11),       # 43 +
    (0xfa, 8),         # 44 ,
    (0x16, 6),         # 45 -
    (0x17, 6),         # 46 .
    (0x18, 6),         # 47 /
    # 48-63: 0-9 : ; < = > ?
    (0x0, 5),          # 48 0
    (0x1, 5),          # 49 1
    (0x2, 5),          # 50 2
    (0x19, 6),         # 51 3
    (0x1a, 6),         # 52 4
    (0x1b, 6),         # 53 5
    (0x1c, 6),         # 54 6
    (0x1d, 6),         # 55 7
    (0x1e, 6),         # 56 8
    (0x1f, 6),         # 57 9
    (0x5c, 7),         # 58 :
    (0xfb, 8),         # 59 ;
    (0x7ffc, 15),      # 60 <
    (0x20, 6),         # 61 =
    (0xffb, 12),       # 62 >
    (0x3fc, 10),       # 63 ?
    # 64-79: @ A-O
    (0x1ffa, 13),      # 64 @
    (0x21, 6),         # 65 A
    (0x5d, 7),         # 66 B
    (0x5e, 7),         # 67 C
    (0x5f, 7),         # 68 D
    (0x60, 7),         # 69 E
    (0x61, 7),         # 70 F
    (0x62, 7),         # 71 G
    (0x63, 7),         # 72 H
    (0x64, 7),         # 73 I
    (0x65, 7),         # 74 J
    (0x66, 7),         # 75 K
    (0x67, 7),         # 76 L
    (0x68, 7),         # 77 M
    (0x69, 7),         # 78 N
    (0x6a, 7),         # 79 O
    # 80-95: P-Z [ \ ] ^ _
    (0x6b, 7),         # 80 P
    (0x6c, 7),         # 81 Q
    (0x6d, 7),         # 82 R
    (0x6e, 7),         # 83 S
    (0x6f, 7),         # 84 T
    (0x70, 7),         # 85 U
    (0x71, 7),         # 86 V
    (0x72, 7),         # 87 W
    (0xfc, 8),         # 88 X
    (0x73, 7),         # 89 Y
    (0xfd, 8),         # 90 Z
    (0x1ffb, 13),      # 91 [
    (0x7fff0, 19),     # 92 \
    (0x1ffc, 13),      # 93 ]
    (0x3ffc, 14),      # 94 ^
    (0x22, 6),         # 95 _
    # 96-111: ` a-o
    (0x7ffd, 15),      # 96 `
    (0x3, 5),          # 97 a
    (0x23, 6),         # 98 b
    (0x4, 5),          # 99 c
    (0x24, 6),         # 100 d
    (0x5, 5),          # 101 e
    (0x25, 6),         # 102 f
    (0x26, 6),         # 103 g
    (0x27, 6),         # 104 h
    (0x6, 5),          # 105 i
    (0x74, 7),         # 106 j
    (0x75, 7),         # 107 k
    (0x28, 6),         # 108 l
    (0x29, 6),         # 109 m
    (0x2a, 6),         # 110 n
    (0x7, 5),          # 111 o
    # 112-127: p-z { | } ~ DEL
    (0x2b, 6),         # 112 p
    (0x76, 7),         # 113 q
    (0x2c, 6),         # 114 r
    (0x8, 5),          # 115 s
    (0x9, 5),          # 116 t
    (0x2d, 6),         # 117 u
    (0x77, 7),         # 118 v
    (0x78, 7),         # 119 w
    (0x79, 7),         # 120 x
    (0x7a, 7),         # 121 y
    (0x7b, 7),         # 122 z
    (0x7ffe, 15),      # 123 {
    (0x7fc, 11),       # 124 |
    (0x3ffd, 14),      # 125 }
    (0x1ffd, 13),      # 126 ~
    (0xffffffc, 28),   # 127 DEL
    # 128-143
    (0xfffe6, 20),     # 128
    (0x3fffd2, 22),    # 129
    (0xfffe7, 20),     # 130
    (0xfffe8, 20),     # 131
    (0x3fffd3, 22),    # 132
    (0x3fffd4, 22),    # 133
    (0x3fffd5, 22),    # 134
    (0x7fffd9, 23),    # 135
    (0x3fffd6, 22),    # 136
    (0x7fffda, 23),    # 137
    (0x7fffdb, 23),    # 138
    (0x7fffdc, 23),    # 139
    (0x7fffdd, 23),    # 140
    (0x7fffde, 23),    # 141
    (0xffffeb, 24),    # 142
    (0x7fffdf, 23),    # 143
    # 144-159
    (0xffffec, 24),    # 144
    (0xffffed, 24),    # 145
    (0x3fffd7, 22),    # 146
    (0x7fffe0, 23),    # 147
    (0xffffee, 24),    # 148
    (0x7fffe1, 23),    # 149
    (0x7fffe2, 23),    # 150
    (0x7fffe3, 23),    # 151
    (0x7fffe4, 23),    # 152
    (0x1fffdc, 21),    # 153
    (0x3fffd8, 22),    # 154
    (0x7fffe5, 23),    # 155
    (0x3fffd9, 22),    # 156
    (0x7fffe6, 23),    # 157
    (0x7fffe7, 23),    # 158
    (0xffffef, 24),    # 159
    # 160-175
    (0x3fffda, 22),    # 160
    (0x1fffdd, 21),    # 161
    (0xfffe9, 20),     # 162
    (0x3fffdb, 22),    # 163
    (0x3fffdc, 22),    # 164
    (0x7fffe8, 23),    # 165
    (0x7fffe9, 23),    # 166
    (0x1fffde, 21),    # 167
    (0x7fffea, 23),    # 168
    (0x3fffdd, 22),    # 169
    (0x3fffde, 22),    # 170
    (0xfffff0, 24),    # 171
    (0x1fffdf, 21),    # 172
    (0x3fffdf, 22),    # 173
    (0x7fffeb, 23),    # 174
    (0x7fffec, 23),    # 175
    # 176-191
    (0x1fffe0, 21),    # 176
    (0x1fffe1, 21),    # 177
    (0x3fffe0, 22),    # 178
    (0x1fffe2, 21),    # 179
    (0x7fffed, 23),    # 180
    (0x3fffe1, 22),    # 181
    (0x7fffee, 23),    # 182
    (0x7fffef, 23),    # 183
    (0xfffea, 20),     # 184
    (0x3fffe2, 22),    # 185
    (0x3fffe3, 22),    # 186
    (0x3fffe4, 22),    # 187
    (0x7ffff0, 23),    # 188
    (0x3fffe5, 22),    # 189
    (0x3fffe6, 22),    # 190
    (0x7ffff1, 23),    # 191
    # 192-207
    (0x3ffffe0, 26),   # 192
    (0x3ffffe1, 26),   # 193
    (0xfffeb, 20),     # 194
    (0x7fff1, 19),     # 195
    (0x3fffe7, 22),    # 196
    (0x7ffff2, 23),    # 197
    (0x3fffe8, 22),    # 198
    (0x1ffffec, 25),   # 199
    (0x3ffffe2, 26),   # 200
    (0x3ffffe3, 26),   # 201
    (0x3ffffe4, 26),   # 202
    (0x7ffffde, 27),   # 203
    (0x7ffffdf, 27),   # 204
    (0x3ffffe5, 26),   # 205
    (0xfffff1, 24),    # 206
    (0x1ffffed, 25),   # 207
    # 208-223
    (0x7fff2, 19),     # 208
    (0x1fffe3, 21),    # 209
    (0x3ffffe6, 26),   # 210
    (0x7ffffe0, 27),   # 211
    (0x7ffffe1, 27),   # 212
    (0x3ffffe7, 26),   # 213
    (0x7ffffe2, 27),   # 214
    (0xfffff2, 24),    # 215
    (0x1fffe4, 21),    # 216
    (0x1fffe5, 21),    # 217
    (0x3ffffe8, 26),   # 218
    (0x3ffffe9, 26),   # 219
    (0xffffffd, 28),   # 220
    (0x7ffffe3, 27),   # 221
    (0x7ffffe4, 27),   # 222
    (0x7ffffe5, 27),   # 223
    # 224-239
    (0xfffec, 20),     # 224
    (0xfffff3, 24),    # 225
    (0xfffed, 20),     # 226
    (0x1fffe6, 21),    # 227
    (0x3fffe9, 22),    # 228
    (0x1fffe7, 21),    # 229
    (0x1fffe8, 21),    # 230
    (0x7ffff3, 23),    # 231
    (0x3fffea, 22),    # 232
    (0x3fffeb, 22),    # 233
    (0x1ffffee, 25),   # 234
    (0x1ffffef, 25),   # 235
    (0xfffff4, 24),    # 236
    (0xfffff5, 24),    # 237
    (0x3ffffea, 26),   # 238
    (0x7ffff4, 23),    # 239
    # 240-255
    (0x3ffffeb, 26),   # 240
    (0x7ffffe6, 27),   # 241
    (0x3ffffec, 26),   # 242
    (0x3ffffed, 26),   # 243
    (0x7ffffe7, 27),   # 244
    (0x7ffffe8, 27),   # 245
    (0x7ffffe9, 27),   # 246
    (0x7ffffea, 27),   # 247
    (0x7ffffeb, 27),   # 248
    (0xffffffe, 28),   # 249
    (0x7ffffec, 27),   # 250
    (0x7ffffed, 27),   # 251
    (0x7ffffee, 27),   # 252
    (0x7ffffef, 27),   # 253
    (0x7fffff0, 27),   # 254
    (0x3ffffee, 26),   # 255
    # EOS (256)
    (0x3fffffff, 30),  # 256 EOS
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

"""
    huffman_encode(data::AbstractVector{UInt8}) -> Vector{UInt8}

Encode data using Huffman encoding per RFC 7541 Appendix B.
Returns the Huffman-encoded bytes with proper padding.
"""
function huffman_encode(data::AbstractVector{UInt8})::Vector{UInt8}
    result = UInt8[]
    buffer = UInt64(0)  # Bit buffer for accumulating bits
    bits_in_buffer = 0

    for byte in data
        # Get Huffman code and length for this byte (1-indexed in Julia)
        code, code_bits = HUFFMAN_CODES[Int(byte) + 1]

        # Add code bits to buffer
        buffer = (buffer << code_bits) | UInt64(code)
        bits_in_buffer += code_bits

        # Extract complete bytes from buffer
        while bits_in_buffer >= 8
            bits_in_buffer -= 8
            push!(result, UInt8((buffer >> bits_in_buffer) & 0xFF))
        end
    end

    # Handle remaining bits - pad with EOS prefix (all 1s)
    if bits_in_buffer > 0
        # Pad remaining bits with 1s (EOS prefix)
        padding_bits = 8 - bits_in_buffer
        buffer = (buffer << padding_bits) | ((1 << padding_bits) - 1)
        push!(result, UInt8(buffer & 0xFF))
    end

    return result
end

"""
    huffman_encoded_length(data::AbstractVector{UInt8}) -> Int

Calculate the length of Huffman-encoded data without actually encoding.
Used to decide whether Huffman encoding saves space.
"""
function huffman_encoded_length(data::AbstractVector{UInt8})::Int
    total_bits = 0
    for byte in data
        _, code_bits = HUFFMAN_CODES[Int(byte) + 1]
        total_bits += code_bits
    end
    # Round up to bytes
    return (total_bits + 7) ÷ 8
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
Supports both raw and Huffman encoding per RFC 7541 Section 5.2.

When `huffman=true`, the string is Huffman-encoded if it saves space.
"""
function encode_string(s::String; huffman::Bool=false)::Vector{UInt8}
    raw_data = Vector{UInt8}(s)

    if huffman
        # Encode with Huffman and check if it saves space
        encoded_data = huffman_encode(raw_data)
        if length(encoded_data) < length(raw_data)
            # Use Huffman encoding - saves space
            length_bytes = encode_integer(length(encoded_data), 7)
            length_bytes[1] |= 0x80  # Set Huffman flag (H bit)
            return vcat(length_bytes, encoded_data)
        end
        # Huffman doesn't save space, fall through to raw encoding
    end

    # Raw encoding (no Huffman)
    length_bytes = encode_integer(length(raw_data), 7)
    length_bytes[1] &= 0x7F  # Clear Huffman flag
    return vcat(length_bytes, raw_data)
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
