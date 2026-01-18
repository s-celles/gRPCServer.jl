# HPACK Test Vectors

This directory contains test vectors from the [http2jp/hpack-test-case](https://github.com/http2jp/hpack-test-case) repository.

## Purpose

These test vectors validate HPACK encoder/decoder implementations against canonical test cases created by various HTTP/2 implementations. Each directory contains the same header data encoded using different strategies:

- **nghttp2/**: Reference C implementation (widely deployed)
- **go-hpack/**: Go standard library implementation
- **python-hpack/**: Python hyper-h2 implementation
- **raw-data/**: Original unencoded headers (for round-trip testing)

## Test File Format

Each `story_XX.json` file contains:

```json
{
  "description": "Encoding strategy description",
  "cases": [
    {
      "seqno": 0,
      "wire": "82864188f439ce75c875fa5784",
      "headers": [
        {":method": "GET"},
        {":scheme": "http"},
        {":authority": "example.com"},
        {":path": "/"}
      ],
      "header_table_size": 4096
    }
  ]
}
```

- `seqno`: Sequence number (cases share compression context within a file)
- `wire`: Hex-encoded HPACK compressed header block
- `headers`: Expected decoded headers
- `header_table_size`: Optional dynamic table size setting

## License

The test vectors are from http2jp/hpack-test-case which is licensed under MIT License.

## Reference

- [RFC 7541 - HPACK: Header Compression for HTTP/2](https://tools.ietf.org/html/rfc7541)
- [http2jp/hpack-test-case repository](https://github.com/http2jp/hpack-test-case)
