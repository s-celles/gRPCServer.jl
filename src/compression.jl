# Compression codec support for gRPCServer.jl

using CodecZlib
using TranscodingStreams

"""
    CompressionCodec

Supported compression algorithms for gRPC messages.

# Values
- `IDENTITY`: No compression
- `GZIP`: Gzip compression
- `DEFLATE`: Deflate compression
"""
module CompressionCodec
    @enum T begin
        IDENTITY
        GZIP
        DEFLATE
    end
end

"""
    codec_name(codec::CompressionCodec.T) -> String

Get the gRPC encoding name for a compression codec.
"""
function codec_name(codec::CompressionCodec.T)::String
    if codec == CompressionCodec.IDENTITY
        "identity"
    elseif codec == CompressionCodec.GZIP
        "gzip"
    elseif codec == CompressionCodec.DEFLATE
        "deflate"
    else
        "identity"
    end
end

"""
    parse_codec(name::String) -> Union{CompressionCodec.T, Nothing}

Parse a gRPC encoding name to a compression codec.
Returns `nothing` if the encoding is not supported.
"""
function parse_codec(name::String)::Union{CompressionCodec.T, Nothing}
    name = lowercase(strip(name))
    if name == "identity" || name == ""
        CompressionCodec.IDENTITY
    elseif name == "gzip"
        CompressionCodec.GZIP
    elseif name == "deflate"
        CompressionCodec.DEFLATE
    else
        nothing
    end
end

"""
    parse_accept_encoding(header::String) -> Vector{CompressionCodec.T}

Parse the grpc-accept-encoding header to get list of supported codecs.
"""
function parse_accept_encoding(header::String)::Vector{CompressionCodec.T}
    codecs = CompressionCodec.T[]
    for part in split(header, ",")
        codec = parse_codec(strip(part))
        if codec !== nothing
            push!(codecs, codec)
        end
    end
    return codecs
end

"""
    compress(data::Vector{UInt8}, codec::CompressionCodec.T) -> Vector{UInt8}

Compress data using the specified codec.
"""
function compress(data::Vector{UInt8}, codec::CompressionCodec.T)::Vector{UInt8}
    if codec == CompressionCodec.IDENTITY
        return data
    elseif codec == CompressionCodec.GZIP
        return transcode(GzipCompressor, data)
    elseif codec == CompressionCodec.DEFLATE
        return transcode(DeflateCompressor, data)
    else
        return data
    end
end

"""
    decompress(data::Vector{UInt8}, codec::CompressionCodec.T) -> Vector{UInt8}

Decompress data using the specified codec.
"""
function decompress(data::Vector{UInt8}, codec::CompressionCodec.T)::Vector{UInt8}
    if codec == CompressionCodec.IDENTITY
        return data
    elseif codec == CompressionCodec.GZIP
        return transcode(GzipDecompressor, data)
    elseif codec == CompressionCodec.DEFLATE
        return transcode(DeflateDecompressor, data)
    else
        return data
    end
end

"""
    negotiate_compression(
        client_encodings::Vector{CompressionCodec.T},
        server_codecs::Vector{CompressionCodec.T}
    ) -> CompressionCodec.T

Negotiate compression codec between client and server.
Returns the first codec supported by both, preferring client order.
Falls back to IDENTITY if no common codec.
"""
function negotiate_compression(
    client_encodings::Vector{CompressionCodec.T},
    server_codecs::Vector{CompressionCodec.T}
)::CompressionCodec.T
    for client_codec in client_encodings
        if client_codec in server_codecs
            return client_codec
        end
    end
    return CompressionCodec.IDENTITY
end

"""
    should_compress(data_size::Int, threshold::Int, codec::CompressionCodec.T) -> Bool

Determine if data should be compressed based on size threshold and codec.
"""
function should_compress(data_size::Int, threshold::Int, codec::CompressionCodec.T)::Bool
    codec != CompressionCodec.IDENTITY && data_size >= threshold
end
