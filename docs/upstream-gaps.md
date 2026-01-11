# HTTP/2 Support Gaps in Julia Ecosystem

**Created**: 2026-01-11
**Purpose**: Document HTTP/2 capabilities and gaps in HTTP.jl and related packages to inform gRPCServer.jl implementation decisions.

## Executive Summary

gRPCServer.jl requires HTTP/2 server support to serve gRPC requests. After investigating the Julia ecosystem, we found that **HTTP.jl does not support HTTP/2 server mode**, and the available alternatives are either unmaintained or incomplete. This document provides the analysis and recommendations.

## HTTP.jl Analysis

### Current State (v1.10.19)

| Feature | Client | Server | Notes |
|---------|--------|--------|-------|
| HTTP/1.1 | Yes | Yes | Full support |
| HTTP/2 | Partial | No | Client via LibCURL/Downloads.jl |
| HTTP/3 | No | No | Under discussion |
| WebSocket | Yes | Yes | Full support |

### Relevant Issues/Discussions

1. **[Issue #328](https://github.com/JuliaWeb/HTTP.jl/issues/328)**: "Does it support HTTP/2.0?"
   - Status: Closed (March 2022)
   - Resolution: HTTP/2 client moved to Downloads.jl via LibCURL
   - No server-side HTTP/2 planned

2. **[Discussion #797](https://github.com/JuliaWeb/HTTP.jl/discussions/797)**: HTTP/2/3 Support
   - Status: Open (last activity March 2024)
   - Maintainer expressed interest but no timeline
   - Focus is on client-side, not server-side
   - HTTP/3 may be prioritized over HTTP/2

### Why HTTP.jl Cannot Be Used for gRPCServer.jl

1. **No HTTP/2 server support**: HTTP.jl only supports HTTP/1.1 for server mode
2. **No ALPN negotiation**: Cannot negotiate h2 protocol over TLS
3. **No frame-level API**: Even if HTTP/2 were added, gRPC needs low-level frame access for streaming
4. **No binary framing**: HTTP.jl's server API is text/line oriented for HTTP/1.1

## Alternative Packages

### HTTP2.jl (sorpaas/HTTP2.jl)

| Aspect | Status |
|--------|--------|
| Last Commit | 2016 |
| Julia Compatibility | Julia 0.4-0.5 era |
| Maintenance | Inactive |
| Documentation | Minimal |
| Test Coverage | Unknown |

**Verdict**: Not viable for production use. Would require significant modernization.

### Downloads.jl (JuliaLang/Downloads.jl)

| Feature | Status |
|---------|--------|
| HTTP/2 Client | Yes (via LibCURL) |
| HTTP/2 Server | No |
| gRPC Support | No |

**Verdict**: Useful for HTTP/2 client needs, but provides no server capabilities.

## Feature Gap Summary

### Critical Gaps (Required for gRPCServer.jl)

| Gap | Severity | Workaround |
|-----|----------|------------|
| HTTP/2 server mode | Critical | Custom implementation (current approach) |
| Binary frame processing | Critical | Custom implementation |
| HPACK header compression | Critical | Custom implementation |
| HTTP/2 flow control | Critical | Custom implementation |
| Stream multiplexing | Critical | Custom implementation |

### Nice-to-Have Features

| Gap | Severity | Workaround |
|-----|----------|------------|
| ALPN negotiation | Medium | OpenSSL.jl direct usage |
| HTTP/2 over TLS (h2) | Medium | Manual TLS wrapper |
| Server push | Low | Not needed for gRPC |

## Recommendations

### Short Term (Current)

Continue with the custom HTTP/2 implementation in gRPCServer.jl. The implementation is already 80% complete with:
- Frame parsing/serialization
- HPACK encoding/decoding
- Stream state machine
- Flow control

Only the connection handler integration is missing.

### Medium Term

1. **Extract HTTP/2 code**: Consider extracting the HTTP/2 implementation into a separate package (e.g., `HTTP2Server.jl`) that could be:
   - Maintained independently
   - Used by other Julia packages needing HTTP/2 server support
   - Eventually merged into HTTP.jl if there's interest

2. **Upstream contribution**: If the implementation proves stable, propose contributing server-side HTTP/2 to HTTP.jl. The modular design would allow HTTP.jl to optionally use it.

### Long Term

Monitor HTTP.jl development. If HTTP/2 server support is added upstream:
1. Evaluate API compatibility with gRPC requirements
2. Consider migrating if the API provides sufficient low-level access
3. Maintain custom code as fallback for edge cases

## Potential Upstream Contributions

If contributing to HTTP.jl, these components from gRPCServer.jl could be valuable:

1. **src/http2/frames.jl**: HTTP/2 frame definitions and serialization
2. **src/http2/hpack.jl**: HPACK header compression
3. **src/http2/stream.jl**: Stream state machine
4. **src/http2/flow_control.jl**: Flow control implementation
5. **src/http2/connection.jl**: Connection management

## References

- [HTTP/2 RFC 7540](https://datatracker.ietf.org/doc/html/rfc7540)
- [HPACK RFC 7541](https://datatracker.ietf.org/doc/html/rfc7541)
- [gRPC over HTTP/2](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
- [HTTP.jl Documentation](https://juliaweb.github.io/HTTP.jl/stable/)
- [HTTP.jl GitHub](https://github.com/JuliaWeb/HTTP.jl)
