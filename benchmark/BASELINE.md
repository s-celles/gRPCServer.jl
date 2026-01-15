# Performance Baseline

**Recorded**: 2026-01-15
**Julia Version**: 1.12.x
**System**: Linux x64

This document records baseline performance metrics for gRPCServer.jl.
Use these as a reference when evaluating performance changes.

## Summary

| Category | Benchmark | Median Time | Memory | Allocations |
|----------|-----------|-------------|--------|-------------|
| dispatch | method_lookup | ~28 ns | 96 bytes | 1 |
| dispatch | method_lookup_miss | ~12 ns | 0 bytes | 0 |
| dispatch | context_creation | ~2.1 μs | 2.5 KiB | 57 |
| dispatch | context_simple | ~580 ns | 768 bytes | 7 |
| dispatch | peer_info_creation | ~225 ns | 368 bytes | 3 |
| serialization | serialize_small | ~55 ns | 192 bytes | 4 |
| serialization | deserialize_small | ~135 ns | 128 bytes | 4 |
| serialization | compress_small | ~10.5 μs | 263 KiB | 12 |
| serialization | compress_large (64KB) | ~1.2 ms | 446 KiB | 14 |
| serialization | decompress_small | ~450 ns | 7.4 KiB | 7 |
| serialization | decompress_large (64KB) | ~30 μs | 71 KiB | 8 |
| streaming | stream_creation | ~16 ns | 64 bytes | 2 |
| streaming | send_callback_overhead | ~2.5 ns | 0 bytes | 0 |
| streaming | frame_creation_small | ~23 ns | 192 bytes | 2 |
| streaming | frame_creation_large (64KB) | ~5.7 μs | 64 KiB | 3 |

## Key Metrics

### Request Dispatch
- **Method lookup**: ~28 ns (type-stable hash lookup)
- **Context creation from headers**: ~2.1 μs (includes UUID generation, header parsing)
- **Simple context creation**: ~580 ns

### Message Serialization (ProtoBuf)
- **Small message serialize**: ~55 ns
- **Small message deserialize**: ~135 ns
- **Type registry lookup**: ~13 ns (zero allocations)

### Compression (gzip)
- Compression ratio varies by data; random data compresses poorly
- Real protobuf messages typically compress 2-10x

### Streaming
- **Stream creation**: ~16 ns (minimal overhead)
- **Frame creation**: Linear with message size

## Notes

- All benchmarks use BenchmarkTools.jl with automatic sample sizing
- Results show median values for stability
- Memory and allocation counts are per-operation
- Compression benchmarks use random data (worst case)
- Real-world performance depends on message structure and size

## Regenerating Baseline

```bash
cd benchmark
julia --project benchmarks.jl --save baseline.json
```
