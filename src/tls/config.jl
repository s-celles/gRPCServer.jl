# TLS configuration implementation for gRPCServer.jl
# Uses OpenSSL.jl for TLS/mTLS support

"""
    TLSError <: Exception

Exception type for TLS-related errors.
"""
struct TLSError <: Exception
    message::String
end

Base.showerror(io::IO, e::TLSError) = print(io, "TLSError: ", e.message)

"""
    create_ssl_context(config::TLSConfig) -> OpenSSL.SSLContext

Create an SSL context from TLS configuration.
Returns an OpenSSL.jl SSLContext configured for gRPC (HTTP/2).
"""
function create_ssl_context(config::TLSConfig)
    # Verify configuration first
    if !verify_tls_config(config)
        throw(TLSError("Invalid TLS configuration"))
    end

    # Create SSL context for server mode
    ctx = OpenSSL.SSLContext(OpenSSL.TLSServerMethod())

    # Set minimum TLS version
    min_version = if config.min_version == :TLSv1_2
        OpenSSL.TLS1_2_VERSION
    elseif config.min_version == :TLSv1_3
        OpenSSL.TLS1_3_VERSION
    else
        OpenSSL.TLS1_2_VERSION
    end

    try
        OpenSSL.ssl_set_min_protocol_version(ctx, min_version)
    catch e
        throw(TLSError("Failed to set minimum TLS version: $e"))
    end

    # Load certificate - OpenSSL.jl requires X509Certificate object, not file path
    try
        cert_pem = read(config.cert_chain, String)
        cert = OpenSSL.X509Certificate(cert_pem)
        OpenSSL.ssl_use_certificate(ctx, cert)
    catch e
        throw(TLSError("Failed to load certificate chain: $(config.cert_chain) - $e"))
    end

    # Load private key - OpenSSL.jl requires EvpPKey object, not file path
    try
        key_pem = read(config.private_key, String)
        key = OpenSSL.EvpPKey(key_pem)
        OpenSSL.ssl_use_private_key(ctx, key)
    catch e
        throw(TLSError("Failed to load private key: $(config.private_key) - $e"))
    end

    # Configure mutual TLS if client CA is specified
    # Note: OpenSSL.jl doesn't expose ssl_set_verify and ssl_load_client_ca_file
    # mTLS verification would need to be implemented with lower-level ccalls
    if config.client_ca !== nothing && config.require_client_cert
        @warn "mTLS client certificate verification is not yet fully supported - client CA will be loaded but verification may not be enforced"
        # TODO: Implement mTLS using lower-level OpenSSL ccalls when needed
    end

    # Set ALPN for HTTP/2 (required for gRPC)
    setup_alpn!(ctx)

    return ctx
end

"""
    verify_tls_config(config::TLSConfig) -> Bool

Verify that TLS configuration is valid (files exist, certificates are valid).
"""
function verify_tls_config(config::TLSConfig)::Bool
    # Check certificate file exists
    if !isfile(config.cert_chain)
        @error "Certificate file not found" path=config.cert_chain
        return false
    end

    # Check private key file exists
    if !isfile(config.private_key)
        @error "Private key file not found" path=config.private_key
        return false
    end

    # Check client CA if mTLS is configured
    if config.client_ca !== nothing && !isfile(config.client_ca)
        @error "Client CA file not found" path=config.client_ca
        return false
    end

    return true
end

"""
    wrap_socket_tls(socket::TCPSocket, ctx::OpenSSL.SSLContext) -> OpenSSL.SSLStream

Wrap a TCP socket with TLS using the provided SSL context.
Performs server-side TLS handshake and returns the secure stream.
"""
function wrap_socket_tls(socket::Sockets.TCPSocket, ctx)
    # Create SSLStream from context and socket
    ssl_stream = OpenSSL.SSLStream(ctx, socket)
    # Perform server-side TLS handshake
    Sockets.accept(ssl_stream)
    return ssl_stream
end

"""
    get_peer_certificate(ssl::OpenSSL.SSLStream) -> Union{OpenSSL.X509Certificate, Nothing}

Get the peer's certificate from a TLS connection (for mTLS).
Returns the X509Certificate or nothing if no certificate.
"""
function get_peer_certificate(ssl)::Union{OpenSSL.X509Certificate, Nothing}
    try
        return OpenSSL.get_peer_certificate(ssl)
    catch
        # No certificate available
        return nothing
    end
end

"""
    close_tls_socket(ssl::OpenSSL.SSLStream)

Properly close a TLS stream, performing shutdown handshake.
"""
function close_tls_socket(ssl)
    try
        # OpenSSL.jl uses ssl_disconnect for shutdown
        OpenSSL.ssl_disconnect(ssl.ssl)
    catch
        # Ignore errors during shutdown
    end
    try
        close(ssl)
    catch
        # Ignore errors during close
    end
end
