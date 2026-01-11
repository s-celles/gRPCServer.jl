# Roadmap

This document outlines planned improvements and missing features for gRPCServer.jl based on the project constitution requirements.

## High Priority

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

**Status**: Partially Complete

The CI builds documentation but uses `warnonly` for missing docs and cross-references. The constitution requires documentation build to fail on errors.

**Tasks**:
- [ ] Review and add missing docstrings for exported symbols
- [ ] Fix any broken cross-references
- [ ] Remove `warnonly` from `docs/make.jl` once all issues are resolved

## Medium Priority

### Code Coverage Improvements

**Status**: Ongoing

The constitution recommends >80% code coverage for non-generated code.

**Tasks**:
- [ ] Review current coverage reports
- [ ] Add tests for uncovered error paths
- [ ] Add tests for edge cases in HTTP/2 frame handling

### Performance Benchmarks

**Status**: Not Started

The constitution requires benchmark comparisons for performance-critical changes.

**Tasks**:
- [ ] Create benchmark suite using BenchmarkTools.jl
- [ ] Benchmark request dispatch latency
- [ ] Benchmark streaming throughput
- [ ] Benchmark message serialization overhead
- [ ] Document baseline performance metrics

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

---

*Last updated: 2026-01-11*
