# ALPN negotiation for HTTP/2 in gRPCServer.jl
# Uses OpenSSL.jl for ALPN support

"""
    ALPN_PROTOCOLS

ALPN protocols for gRPC over HTTP/2.
"""
const ALPN_PROTOCOLS = ["h2"]

"""
    setup_alpn!(ssl_ctx, protocols::Vector{String}=ALPN_PROTOCOLS)

Configure ALPN on an SSL context for HTTP/2 negotiation.
This is required for gRPC which mandates HTTP/2 transport.
"""
function setup_alpn!(ssl_ctx, protocols::Vector{String}=ALPN_PROTOCOLS)
    try
        # OpenSSL ALPN expects wire-format: length-prefixed strings
        alpn_data = UInt8[]
        for proto in protocols
            push!(alpn_data, UInt8(length(proto)))
            append!(alpn_data, Vector{UInt8}(proto))
        end
        OpenSSL.ssl_set_alpn_protos(ssl_ctx, alpn_data)
    catch e
        @warn "Failed to set ALPN protocols" exception=e
    end
    return nothing
end

"""
    get_negotiated_protocol(ssl) -> Union{String, Nothing}

Get the ALPN-negotiated protocol after handshake.
Returns the protocol name (e.g., "h2") or nothing if no protocol was negotiated.
"""
function get_negotiated_protocol(ssl)::Union{String, Nothing}
    try
        proto = OpenSSL.ssl_get_alpn_selected(ssl)
        if proto !== nothing && !isempty(proto)
            return String(proto)
        end
    catch
        # ALPN not available or not negotiated
    end
    return nothing
end

"""
    verify_http2_negotiated(ssl) -> Bool

Verify that HTTP/2 was negotiated via ALPN.
Returns true if "h2" was negotiated, false otherwise.
"""
function verify_http2_negotiated(ssl)::Bool
    proto = get_negotiated_protocol(ssl)
    return proto == "h2"
end
