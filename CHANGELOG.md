# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CI pipeline now triggers on `develop` branch pushes (in addition to `main` and PRs)
- ROADMAP.md with planned improvements
- CHANGELOG.md for tracking changes
- SECURITY.md with vulnerability reporting policy and security best practices

### Changed
- Documentation build now runs in strict mode (removed `warnonly` from `docs/make.jl`)
- Updated `devbranch` to `develop` in `docs/make.jl` for Git flow compatibility

## [0.1.0] - 2026-01-11

### Added
- Initial release of gRPCServer.jl
- Core gRPC server implementation with `GRPCServer` type
- All four RPC patterns:
  - Unary RPCs
  - Server streaming RPCs
  - Client streaming RPCs
  - Bidirectional streaming RPCs
- HTTP/2 protocol implementation:
  - Frame parsing and serialization
  - HPACK header compression with Huffman encoding
  - Stream multiplexing
  - Flow control
- TLS/mTLS support via OpenSSL.jl:
  - ALPN negotiation for `h2` protocol
  - Certificate reload without restart
  - Client certificate authentication
- Built-in services:
  - Health checking service (`grpc.health.v1.Health`)
  - Server reflection service (`grpc.reflection.v1alpha.ServerReflection`)
  - File descriptor support for reflection
- Interceptor framework:
  - `LoggingInterceptor` for request/response logging
  - `MetricsInterceptor` for timing metrics
  - `TimeoutInterceptor` for deadline enforcement
  - `RecoveryInterceptor` for panic recovery
- Compression support:
  - gzip compression
  - deflate compression
  - Compression negotiation
- Server configuration options:
  - Max message size
  - Max concurrent streams
  - Debug mode
- `ServerContext` with:
  - Request metadata access
  - Response header/trailer setting
  - Cancellation support
  - Deadline/timeout support
- Comprehensive error handling with gRPC status codes
- Type-safe service registration
- Precompilation workload for faster startup
- Documentation with Documenter.jl
- CI/CD with GitHub Actions:
  - Tests on Julia 1.10 LTS and latest stable
  - Tests on Linux, macOS (aarch64), and Windows
  - Automatic documentation deployment

### Documentation
- Quick start guide
- API reference
- Examples for all RPC patterns
- CODE_OF_CONDUCT.md
- CONTRIBUTING.md
- CONTRIBUTORS.md

### Testing
- Aqua.jl quality checks
- Unit tests for all components
- Integration tests for all RPC patterns
- Contract tests with grpcurl

[Unreleased]: https://github.com/s-celles/gRPCServer.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/s-celles/gRPCServer.jl/releases/tag/v0.1.0
