# Roadmap

This document outlines planned improvements and missing features for gRPCServer.jl based on the project constitution requirements.

## High Priority

### Server Streaming RPC Support with grpcurl

**Status**: Complete

Server streaming RPC methods now work correctly via grpcurl.

**Completed**:
- [x] Implement server streaming support in HTTP/2 response handling
- [x] Test with hello_world SayHelloStream example
- [x] Update examples/hello_world/README.md with streaming grpcurl commands

### gRPCClient.jl Integration Tests

**Status**: Not Started

The constitution requires integration tests against [gRPCClient.jl](https://github.com/JuliaIO/gRPCClient.jl) to validate client-server interoperability within the Julia gRPC ecosystem.

**Tasks**:
- [ ] Add gRPCClient.jl as a test dependency
- [ ] Create `test/integration/test_grpcclient.jl`
- [ ] Test all RPC patterns (unary, server streaming, client streaming, bidirectional)
- [ ] Test error handling and status code propagation
- [ ] Test metadata/header passing
- [ ] Test compression negotiation

### Documentation Build Strictness

**Status**: ✅ Complete

The documentation build now runs in strict mode with no `warnonly` exceptions.

**Completed**:
- [x] Verified all exported symbols have docstrings (66 exports, all documented)
- [x] Verified no broken cross-references
- [x] Removed `warnonly` from `docs/make.jl`
- [x] Updated `devbranch` to `develop` for Git flow compatibility

## Medium Priority

### Code Coverage Improvements

**Status**: Ongoing

The constitution recommends >80% code coverage for non-generated code.

**Tasks**:
- [ ] Review current coverage reports
- [ ] Add tests for uncovered error paths
- [ ] Add tests for edge cases in HTTP/2 frame handling

### Performance Benchmarks

**Status**: ✅ Complete

The constitution requires benchmark comparisons for performance-critical changes.

**Completed**:
- [x] Create benchmark suite using BenchmarkTools.jl
- [x] Benchmark request dispatch latency
- [x] Benchmark streaming throughput
- [x] Benchmark message serialization overhead
- [x] Comparison functionality with color-coded output
- [x] Document baseline performance metrics

**Usage**:
```bash
cd benchmark
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project benchmarks.jl
julia --project benchmarks.jl --save baseline.json
julia --project benchmarks.jl --compare baseline.json
```

## Low Priority

### Additional Contract Tests

**Status**: Partially Complete (grpcurl done)

Expand contract testing beyond grpcurl to other reference gRPC implementations.

**Tasks**:
- [ ] Test against official Go gRPC client
- [ ] Test against official Python gRPC client
- [ ] Document interoperability matrix

### TTFX (Time-to-First-Execution) Optimization

**Status**: Partially Complete

The constitution recommends TTFX for basic server startup under 5 seconds.

**Tasks**:
- [ ] Measure current TTFX
- [ ] Optimize precompilation workload if needed
- [ ] Document TTFX metrics

## To Be Considered

### Publishing Internal Project Artifacts

**Status**: Under Consideration

Consider making internal development artifacts publicly available for transparency and community contribution.

**Options**:
- [ ] Publish project constitution (`.specify/memory/constitution.md`)
- [ ] Publish specs/ directory with design documents
- [ ] Include `.proto` files in repository (currently in `specs/*/contracts/`)
- [ ] Alternative: Download `.proto` files from upstream [grpc/grpc](https://github.com/grpc/grpc) repository at build time

**References**:
- [gRPC Health Checking Protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md)
- [gRPC Server Reflection](https://github.com/grpc/grpc/blob/master/doc/server-reflection.md)

### Security Audit

**Status**: Under Consideration

A security audit would help identify vulnerabilities in the HTTP/2 and TLS implementations.

**Options**:
- [ ] Apply for free security audit programs (e.g., OSTIF, Linux Foundation)
- [ ] Community security review
- [ ] Document threat model and security considerations
- [x] Add security policy (SECURITY.md)

**Areas of concern**:
- HTTP/2 frame parsing and validation
- HPACK decompression (potential for compression bombs)
- TLS configuration defaults
- Input validation on gRPC messages

## Completed

- [x] Core gRPC server implementation
- [x] All four RPC patterns (unary, server/client/bidi streaming)
- [x] HTTP/2 protocol support with HPACK compression
- [x] TLS/mTLS support
- [x] Health checking service
- [x] Reflection service with file descriptors
- [x] Interceptor framework
- [x] Compression support (gzip, deflate)
- [x] Aqua.jl quality tests
- [x] Unit tests
- [x] Integration tests
- [x] Contract tests (grpcurl)
- [x] Documentation with Documenter.jl
- [x] CI/CD pipeline
- [x] CODE_OF_CONDUCT.md
- [x] CONTRIBUTING.md
- [x] CONTRIBUTORS.md
- [x] Performance benchmarks (BenchmarkTools.jl)

---

*Last updated: 2026-01-15*
