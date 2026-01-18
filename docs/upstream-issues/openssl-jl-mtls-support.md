# OpenSSL.jl Issue Draft: mTLS Client Certificate Verification Support

**Target Repository**: https://github.com/JuliaWeb/OpenSSL.jl

---

## Title

Feature request: Add bindings for mTLS client certificate verification

## Labels

`enhancement`, `feature request`

## Body

### Summary

I'm working on [gRPCServer.jl](https://github.com/s-celles/gRPCServer.jl), a Julia gRPC server implementation. To support mutual TLS (mTLS) authentication, I need to verify client certificates on the server side. OpenSSL.jl currently lacks the necessary bindings for this functionality.

### Requested Bindings

The following OpenSSL functions would enable mTLS client verification:

1. **`SSL_CTX_set_verify`** - Set verification mode and callback
   - [OpenSSL docs](https://www.openssl.org/docs/man3.0/man3/SSL_CTX_set_verify.html)
   - Needed to require client certificates (`SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT`)

2. **`SSL_CTX_load_verify_locations`** - Load trusted CA certificates
   - [OpenSSL docs](https://www.openssl.org/docs/man3.0/man3/SSL_CTX_load_verify_locations.html)
   - Needed to specify which CA(s) can sign valid client certificates

3. **`SSL_get_verify_result`** - Get verification result after handshake
   - [OpenSSL docs](https://www.openssl.org/docs/man3.0/man3/SSL_get_verify_result.html)
   - Needed to check if client certificate verification succeeded

### Use Case

```julia
# Desired API (illustrative)
ctx = OpenSSL.SSLContext(OpenSSL.TLSServerMethod())

# Load server cert/key (already supported)
OpenSSL.ssl_use_certificate(ctx, cert)
OpenSSL.ssl_use_private_key(ctx, key)

# Configure client verification (not yet supported)
OpenSSL.ssl_ctx_set_verify(ctx, OpenSSL.SSL_VERIFY_PEER | OpenSSL.SSL_VERIFY_FAIL_IF_NO_PEER_CERT)
OpenSSL.ssl_ctx_load_verify_locations(ctx, "/path/to/client-ca.pem")

# After handshake, check result (not yet supported)
result = OpenSSL.ssl_get_verify_result(ssl)
```

### Current Workaround

Currently, gRPCServer.jl can load a client CA file but cannot enforce verification:

```julia
# From src/tls/config.jl
if config.client_ca !== nothing && config.require_client_cert
    @warn "mTLS client certificate verification is not yet fully supported"
    # TODO: Implement mTLS using lower-level OpenSSL ccalls when needed
end
```

### Willingness to Contribute

I'm willing to contribute a PR implementing these bindings if the maintainers are open to it. I'd appreciate guidance on the preferred API style and any design considerations.

### Related

- gRPC requires mTLS for secure service-to-service communication in many deployments
- Other Julia HTTP/TLS packages would benefit from this functionality
- [gRPC Authentication Guide](https://grpc.io/docs/guides/auth/)

### Environment

- Julia: 1.10+ (LTS) and latest stable
- OpenSSL.jl: latest
- OS: Linux, macOS, Windows
