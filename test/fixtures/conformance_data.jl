# Conformance test data constants for gRPC HTTP/2 protocol conformance testing
# Reference: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

"""
Test data constants for gRPC HTTP/2 protocol conformance testing.
"""
module ConformanceData

export TIMEOUT_TEST_CASES, ERROR_MAPPING_TEST_CASES, CONTENT_TYPE_TEST_CASES
export MESSAGE_FRAME_TEST_CASES, VALID_METHODS, INVALID_METHODS
export VALID_PATHS, INVALID_PATHS, HTTP2_ERROR_CODES

# =============================================================================
# Timeout Parsing Test Data
# =============================================================================

"""
Timeout test cases: (input, expected_ms, should_fail)
- input: timeout string (e.g., "1S", "500m")
- expected_ms: expected milliseconds (nothing if invalid)
- should_fail: whether parsing should fail
"""
const TIMEOUT_TEST_CASES = [
    # Valid timeouts
    ("1H", 3600000, false),      # 1 hour
    ("30M", 1800000, false),     # 30 minutes
    ("60S", 60000, false),       # 60 seconds
    ("500m", 500, false),        # 500 milliseconds
    ("1000u", 1, false),         # 1000 microseconds = 1ms (rounded)
    ("1000000n", 1, false),      # 1000000 nanoseconds = 1ms (rounded)
    ("0S", 0, false),            # Zero timeout
    ("100S", 100000, false),     # 100 seconds
    ("1m", 1, false),            # 1 millisecond
    ("10H", 36000000, false),    # 10 hours

    # Invalid timeouts
    ("", nothing, true),         # Empty
    ("1", nothing, true),        # Missing unit
    ("S", nothing, true),        # Missing value
    ("-1S", nothing, true),      # Negative
    ("1X", nothing, true),       # Invalid unit
    ("abc", nothing, true),      # Non-numeric
    ("1.5S", nothing, true),     # Float value (gRPC uses integers)
]

# =============================================================================
# HTTP/2 to gRPC Error Code Mapping Test Data
# =============================================================================

"""
HTTP/2 error codes per RFC 7540 Section 7.
"""
const HTTP2_ERROR_CODES = Dict{UInt32, String}(
    0x00 => "NO_ERROR",
    0x01 => "PROTOCOL_ERROR",
    0x02 => "INTERNAL_ERROR",
    0x03 => "FLOW_CONTROL_ERROR",
    0x04 => "SETTINGS_TIMEOUT",
    0x05 => "STREAM_CLOSED",
    0x06 => "FRAME_SIZE_ERROR",
    0x07 => "REFUSED_STREAM",
    0x08 => "CANCEL",
    0x09 => "COMPRESSION_ERROR",
    0x0A => "CONNECT_ERROR",
    0x0B => "ENHANCE_YOUR_CALM",
    0x0C => "INADEQUATE_SECURITY",
    0x0D => "HTTP_1_1_REQUIRED",
)

"""
Error mapping test cases: (http2_error, http2_name, expected_grpc_status)
Mapping per gRPC HTTP/2 Protocol spec.
"""
const ERROR_MAPPING_TEST_CASES = [
    (0x00, "NO_ERROR", 13),           # INTERNAL
    (0x01, "PROTOCOL_ERROR", 13),     # INTERNAL
    (0x02, "INTERNAL_ERROR", 13),     # INTERNAL
    (0x03, "FLOW_CONTROL_ERROR", 13), # INTERNAL
    (0x04, "SETTINGS_TIMEOUT", 13),   # INTERNAL
    (0x05, "STREAM_CLOSED", 13),      # INTERNAL
    (0x06, "FRAME_SIZE_ERROR", 13),   # INTERNAL
    (0x07, "REFUSED_STREAM", 14),     # UNAVAILABLE
    (0x08, "CANCEL", 1),              # CANCELLED
    (0x09, "COMPRESSION_ERROR", 13),  # INTERNAL
    (0x0A, "CONNECT_ERROR", 13),      # INTERNAL
    (0x0B, "ENHANCE_YOUR_CALM", 8),   # RESOURCE_EXHAUSTED
    (0x0C, "INADEQUATE_SECURITY", 7), # PERMISSION_DENIED
    (0x0D, "HTTP_1_1_REQUIRED", 13),  # INTERNAL (not in spec, default)
]

# =============================================================================
# Content-Type Validation Test Data
# =============================================================================

"""
Content-type test cases: (input, is_valid, normalized_type)
"""
const CONTENT_TYPE_TEST_CASES = [
    # Valid content-types
    ("application/grpc", true, "application/grpc"),
    ("application/grpc+proto", true, "application/grpc+proto"),
    ("application/grpc+json", true, "application/grpc+json"),
    ("application/grpc; charset=utf-8", true, "application/grpc"),
    ("application/grpc+proto; charset=utf-8", true, "application/grpc+proto"),
    ("APPLICATION/GRPC", true, "APPLICATION/GRPC"),  # Case insensitive prefix check

    # Invalid content-types
    ("application/json", false, nothing),
    ("text/plain", false, nothing),
    ("application/protobuf", false, nothing),
    ("", false, nothing),
    ("grpc", false, nothing),
    ("application/grp", false, nothing),  # Missing 'c'
]

# =============================================================================
# Message Framing Test Data
# =============================================================================

"""
Message frame test cases: (input_bytes, expected_compressed, expected_length, expected_message, should_fail)
Format: 1 byte compressed flag + 4 bytes length (big-endian) + message
"""
const MESSAGE_FRAME_TEST_CASES = [
    # Valid frames - uncompressed
    (
        UInt8[0x00, 0x00, 0x00, 0x00, 0x05, 0x01, 0x02, 0x03, 0x04, 0x05],
        0x00,           # Not compressed
        5,              # Length
        UInt8[0x01, 0x02, 0x03, 0x04, 0x05],
        false           # Should not fail
    ),
    # Valid frames - compressed flag set
    (
        UInt8[0x01, 0x00, 0x00, 0x00, 0x03, 0xAA, 0xBB, 0xCC],
        0x01,           # Compressed
        3,              # Length
        UInt8[0xAA, 0xBB, 0xCC],
        false
    ),
    # Empty message
    (
        UInt8[0x00, 0x00, 0x00, 0x00, 0x00],
        0x00,
        0,
        UInt8[],
        false
    ),
    # Large length field (256 bytes)
    (
        vcat(UInt8[0x00, 0x00, 0x00, 0x01, 0x00], zeros(UInt8, 256)),
        0x00,
        256,
        zeros(UInt8, 256),
        false
    ),

    # Invalid frames
    (
        UInt8[0x00, 0x00, 0x00],  # Too short (only 3 bytes, need 5 for header)
        0x00, 0, UInt8[], true
    ),
    (
        UInt8[0x00, 0x00, 0x00, 0x00, 0x05, 0x01, 0x02],  # Truncated message
        0x00, 5, UInt8[], true
    ),
]

# =============================================================================
# HTTP Method Validation Test Data
# =============================================================================

"""
Valid HTTP methods for gRPC (only POST is allowed)
"""
const VALID_METHODS = ["POST"]

"""
Invalid HTTP methods for gRPC
"""
const INVALID_METHODS = [
    "GET",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
]

# =============================================================================
# Path Validation Test Data
# =============================================================================

"""
Valid gRPC path formats: /{service}/{method}
"""
const VALID_PATHS = [
    "/helloworld.Greeter/SayHello",
    "/grpc.health.v1.Health/Check",
    "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo",
    "/pkg.Service/Method",
    "/a/b",  # Minimal valid path
]

"""
Invalid gRPC path formats
Note: gRPC spec is lenient - path must start with "/" and have at least one segment
"""
const INVALID_PATHS = [
    "",                    # Empty
    "/",                   # No service/method (only one slash)
    "/service",            # Missing method (only one segment - actually has only 1 slash)
    "service/method",      # Missing leading slash
]

# =============================================================================
# TE Header Test Data
# =============================================================================

"""
Valid TE header values
"""
const VALID_TE_HEADERS = ["trailers"]

"""
Invalid/missing TE header scenarios
"""
const INVALID_TE_HEADERS = [
    "",           # Empty
    "chunked",    # Wrong value
    "gzip",       # Wrong value
    nothing,      # Missing header (represented as nothing)
]

# =============================================================================
# Binary Metadata Test Data
# =============================================================================

"""
Binary metadata test cases: (header_name, raw_value, is_binary, expected_decoded)
Binary headers must have "-bin" suffix and are base64 encoded.
"""
const BINARY_METADATA_TEST_CASES = [
    ("x-custom-bin", "AQIDBA==", true, UInt8[0x01, 0x02, 0x03, 0x04]),
    ("x-trace-bin", "dGVzdA==", true, UInt8[0x74, 0x65, 0x73, 0x74]),  # "test"
    ("x-custom", "plain-text", false, "plain-text"),
    ("authorization", "Bearer token123", false, "Bearer token123"),
]

# =============================================================================
# gRPC Status Codes
# =============================================================================

"""
gRPC status codes per specification.
"""
const GRPC_STATUS_CODES = Dict{Int, String}(
    0 => "OK",
    1 => "CANCELLED",
    2 => "UNKNOWN",
    3 => "INVALID_ARGUMENT",
    4 => "DEADLINE_EXCEEDED",
    5 => "NOT_FOUND",
    6 => "ALREADY_EXISTS",
    7 => "PERMISSION_DENIED",
    8 => "RESOURCE_EXHAUSTED",
    9 => "FAILED_PRECONDITION",
    10 => "ABORTED",
    11 => "OUT_OF_RANGE",
    12 => "UNIMPLEMENTED",
    13 => "INTERNAL",
    14 => "UNAVAILABLE",
    15 => "DATA_LOSS",
    16 => "UNAUTHENTICATED",
)

end # module ConformanceData
