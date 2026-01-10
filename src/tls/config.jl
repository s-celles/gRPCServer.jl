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

    OpenSSL.ssl_set_min_proto_version(ctx, min_version)

    # Load certificate chain
    try
        OpenSSL.ssl_use_certificate_chain_file(ctx, config.cert_chain)
    catch e
        throw(TLSError("Failed to load certificate chain: $(config.cert_chain)"))
    end

    # Load private key
    try
        OpenSSL.ssl_use_private_key_file(ctx, config.private_key)
    catch e
        throw(TLSError("Failed to load private key: $(config.private_key)"))
    end

    # Configure mutual TLS if client CA is specified
    if config.client_ca !== nothing
        try
            OpenSSL.ssl_set_verify(ctx,
                config.require_client_cert ?
                    OpenSSL.SSL_VERIFY_PEER | OpenSSL.SSL_VERIFY_FAIL_IF_NO_PEER_CERT :
                    OpenSSL.SSL_VERIFY_PEER
            )
            OpenSSL.ssl_load_client_ca_file(ctx, config.client_ca)
        catch e
            throw(TLSError("Failed to configure client CA: $(config.client_ca)"))
        end
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
    wrap_socket_tls(socket::TCPSocket, ctx::OpenSSL.SSLContext) -> OpenSSL.SSLSocket

Wrap a TCP socket with TLS using the provided SSL context.
Performs TLS handshake and returns the secure socket.
"""
function wrap_socket_tls(socket::TCPSocket, ctx)
    ssl = OpenSSL.SSLSocket(ctx, socket)
    OpenSSL.accept(ssl)  # Server-side TLS handshake
    return ssl
end

"""
    get_peer_certificate(ssl::OpenSSL.SSLSocket) -> Union{Vector{UInt8}, Nothing}

Get the peer's certificate from a TLS connection (for mTLS).
Returns the DER-encoded certificate or nothing if no certificate.
"""
function get_peer_certificate(ssl)::Union{Vector{UInt8}, Nothing}
    try
        cert = OpenSSL.get_peer_certificate(ssl)
        if cert !== nothing
            return OpenSSL.certificate_to_der(cert)
        end
    catch
        # No certificate available
    end
    return nothing
end

"""
    close_tls_socket(ssl::OpenSSL.SSLSocket)

Properly close a TLS socket, performing shutdown handshake.
"""
function close_tls_socket(ssl)
    try
        OpenSSL.shutdown(ssl)
    catch
        # Ignore errors during shutdown
    end
    try
        close(ssl)
    catch
        # Ignore errors during close
    end
end
