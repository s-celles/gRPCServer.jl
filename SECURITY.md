# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### How to Report

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to the maintainers. You can find maintainer contact information in the [CONTRIBUTORS.md](CONTRIBUTORS.md) file.

When reporting, please include:

1. **Description**: A clear description of the vulnerability
2. **Impact**: The potential impact if exploited
3. **Reproduction steps**: Detailed steps to reproduce the issue
4. **Affected versions**: Which versions are affected
5. **Suggested fix**: If you have one (optional)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt within 48 hours
- **Assessment**: We will assess the vulnerability and determine its severity
- **Updates**: We will keep you informed of our progress
- **Resolution**: We aim to resolve critical issues within 30 days
- **Credit**: With your permission, we will credit you in the security advisory

## Security Considerations

### Areas of Potential Concern

gRPCServer.jl implements network protocols that require careful security consideration:

#### HTTP/2 Protocol
- Frame parsing and validation
- Stream multiplexing limits
- Flow control enforcement
- Header size limits

#### HPACK Compression
- Dynamic table size limits (potential for memory exhaustion)
- Huffman decoding validation
- Protection against compression bombs

#### TLS/mTLS
- Certificate validation
- Cipher suite selection
- Protocol version enforcement
- ALPN negotiation

#### gRPC Layer
- Message size limits (`max_message_size` configuration)
- Concurrent stream limits (`max_concurrent_streams` configuration)
- Input validation on protobuf messages
- Error message information disclosure (controlled via `debug_mode`)

### Security Best Practices

When deploying gRPCServer.jl in production:

1. **Enable TLS**: Always use TLS in production environments
   ```julia
   tls_config = TLSConfig(
       cert_chain = "/path/to/cert.pem",
       private_key = "/path/to/key.pem",
       min_version = :TLSv1_2
   )
   server = GRPCServer(host, port; tls = tls_config)
   ```

2. **Disable debug mode**: Never enable `debug_mode` in production
   ```julia
   server = GRPCServer(host, port; debug_mode = false)
   ```

3. **Set appropriate limits**: Configure message and stream limits
   ```julia
   server = GRPCServer(host, port;
       max_message_size = 4 * 1024 * 1024,  # 4MB
       max_concurrent_streams = 100
   )
   ```

4. **Use mTLS for service-to-service**: Enable client certificate authentication
   ```julia
   tls_config = TLSConfig(
       cert_chain = "/path/to/cert.pem",
       private_key = "/path/to/key.pem",
       client_ca = "/path/to/ca.pem",
       require_client_cert = true
   )
   ```

5. **Implement authentication interceptors**: Add authentication logic
   ```julia
   struct AuthInterceptor <: Interceptor end

   function (::AuthInterceptor)(ctx, request, info, next)
       token = get_metadata_string(ctx, "authorization")
       if !validate_token(token)
           throw(GRPCError(StatusCode.UNAUTHENTICATED, "Invalid token"))
       end
       return next(ctx, request)
   end
   ```

## Dependencies

gRPCServer.jl depends on:

- **ProtoBuf.jl**: Message serialization
- **OpenSSL.jl**: TLS implementation
- **CodecZlib.jl**: Compression

Security vulnerabilities in these dependencies may affect gRPCServer.jl. We monitor for updates and will release patches as needed.

## Audit Status

This project has not yet undergone a formal security audit. See [ROADMAP.md](ROADMAP.md) for plans regarding security review.

## Acknowledgments

We thank the security researchers who help keep gRPCServer.jl secure. Contributors will be acknowledged here (with permission).

<!-- Security acknowledgments will be listed here -->
