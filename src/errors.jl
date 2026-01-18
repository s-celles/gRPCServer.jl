# Error types and status codes for gRPCServer.jl

"""
    StatusCode

Standard gRPC status codes per specification.

# Status Codes
- `OK` (0): Not an error; returned on success
- `CANCELLED` (1): Operation was cancelled
- `UNKNOWN` (2): Unknown error
- `INVALID_ARGUMENT` (3): Invalid argument provided
- `DEADLINE_EXCEEDED` (4): Deadline expired before completion
- `NOT_FOUND` (5): Requested entity not found
- `ALREADY_EXISTS` (6): Entity already exists
- `PERMISSION_DENIED` (7): Permission denied
- `RESOURCE_EXHAUSTED` (8): Resource exhausted
- `FAILED_PRECONDITION` (9): Precondition check failed
- `ABORTED` (10): Operation aborted
- `OUT_OF_RANGE` (11): Value out of range
- `UNIMPLEMENTED` (12): Operation not implemented
- `INTERNAL` (13): Internal error
- `UNAVAILABLE` (14): Service unavailable
- `DATA_LOSS` (15): Data loss or corruption
- `UNAUTHENTICATED` (16): Request not authenticated
"""
module StatusCode
    @enum T::Int32 begin
        OK = 0
        CANCELLED = 1
        UNKNOWN = 2
        INVALID_ARGUMENT = 3
        DEADLINE_EXCEEDED = 4
        NOT_FOUND = 5
        ALREADY_EXISTS = 6
        PERMISSION_DENIED = 7
        RESOURCE_EXHAUSTED = 8
        FAILED_PRECONDITION = 9
        ABORTED = 10
        OUT_OF_RANGE = 11
        UNIMPLEMENTED = 12
        INTERNAL = 13
        UNAVAILABLE = 14
        DATA_LOSS = 15
        UNAUTHENTICATED = 16
    end
end

"""
    GRPCError <: Exception

Exception type for gRPC errors with status code, message, and optional details.

# Fields
- `code::StatusCode.T`: The gRPC status code
- `message::String`: Human-readable error message
- `details::Vector{Any}`: Additional error details (rich error model)

# Example
```julia
throw(GRPCError(StatusCode.NOT_FOUND, "User not found", []))
throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Name cannot be empty"))
```
"""
struct GRPCError <: Exception
    code::StatusCode.T
    message::String
    details::Vector{Any}

    GRPCError(code::StatusCode.T, message::String, details::Vector{Any}=Any[]) =
        new(code, message, details)
end

function Base.showerror(io::IO, e::GRPCError)
    print(io, "GRPCError: [", e.code, "] ", e.message)
    if !isempty(e.details)
        print(io, " (", length(e.details), " detail(s))")
    end
end

"""
    BindError <: Exception

Exception thrown when the server fails to bind to the configured address.

# Fields
- `message::String`: Description of the bind failure
- `cause::Union{Exception, Nothing}`: Underlying exception if available
"""
struct BindError <: Exception
    message::String
    cause::Union{Exception, Nothing}

    BindError(message::String, cause::Union{Exception, Nothing}=nothing) =
        new(message, cause)
end

function Base.showerror(io::IO, e::BindError)
    print(io, "BindError: ", e.message)
    if e.cause !== nothing
        print(io, "\n  Caused by: ")
        showerror(io, e.cause)
    end
end

"""
    InvalidServerStateError <: Exception

Exception thrown when an operation is attempted in an invalid server state.

# Fields
- `expected::ServerStatus.T`: The expected server state
- `actual::ServerStatus.T`: The actual server state
"""
struct InvalidServerStateError <: Exception
    expected::Symbol
    actual::Symbol
end

function Base.showerror(io::IO, e::InvalidServerStateError)
    print(io, "InvalidServerStateError: expected server to be ", e.expected,
          ", but was ", e.actual)
end

"""
    ServiceAlreadyRegisteredError <: Exception

Exception thrown when attempting to register a service with a name that already exists.

# Fields
- `service_name::String`: The duplicate service name
"""
struct ServiceAlreadyRegisteredError <: Exception
    service_name::String
end

function Base.showerror(io::IO, e::ServiceAlreadyRegisteredError)
    print(io, "ServiceAlreadyRegisteredError: service '", e.service_name,
          "' is already registered")
end

"""
    MethodSignatureError <: Exception

Exception thrown when a handler method has an invalid signature.

# Fields
- `method_name::String`: The method with invalid signature
- `expected::String`: Description of expected signature
- `actual::String`: Description of actual signature
"""
struct MethodSignatureError <: Exception
    method_name::String
    expected::String
    actual::String
end

function Base.showerror(io::IO, e::MethodSignatureError)
    print(io, "MethodSignatureError: method '", e.method_name, "'\n",
          "  Expected: ", e.expected, "\n",
          "  Actual: ", e.actual)
end

"""
    StreamCancelledError <: Exception

Exception thrown when a stream operation is attempted on a cancelled stream.

# Fields
- `reason::String`: The reason for cancellation
"""
struct StreamCancelledError <: Exception
    reason::String
end

function Base.showerror(io::IO, e::StreamCancelledError)
    print(io, "StreamCancelledError: ", e.reason)
end

"""
    status_code_to_http(code::StatusCode.T) -> Int

Map a gRPC status code to the appropriate HTTP status code.
"""
function status_code_to_http(code::StatusCode.T)::Int
    return if code == StatusCode.OK
        200
    elseif code == StatusCode.INVALID_ARGUMENT
        400
    elseif code == StatusCode.UNAUTHENTICATED
        401
    elseif code == StatusCode.PERMISSION_DENIED
        403
    elseif code == StatusCode.NOT_FOUND
        404
    elseif code == StatusCode.ALREADY_EXISTS
        409
    elseif code == StatusCode.RESOURCE_EXHAUSTED
        429
    elseif code == StatusCode.CANCELLED
        499
    elseif code == StatusCode.UNIMPLEMENTED
        501
    elseif code == StatusCode.UNAVAILABLE
        503
    elseif code == StatusCode.DEADLINE_EXCEEDED
        504
    else
        500  # INTERNAL, UNKNOWN, etc.
    end
end

"""
    exception_to_status_code(e::Exception) -> StatusCode.T

Map a Julia exception to a gRPC status code.
"""
function exception_to_status_code(e::Exception)::StatusCode.T
    if e isa GRPCError
        return e.code
    elseif e isa ArgumentError
        return StatusCode.INVALID_ARGUMENT
    elseif e isa BoundsError
        return StatusCode.OUT_OF_RANGE
    elseif e isa KeyError
        return StatusCode.NOT_FOUND
    elseif e isa InterruptException
        return StatusCode.CANCELLED
    else
        return StatusCode.INTERNAL
    end
end

# HTTP/2 error code constants for mapping (duplicated from frames.jl for isolation)
const _HTTP2_REFUSED_STREAM = 0x07
const _HTTP2_CANCEL = 0x08
const _HTTP2_ENHANCE_YOUR_CALM = 0x0b
const _HTTP2_INADEQUATE_SECURITY = 0x0c

"""
    http2_to_grpc_status(http2_error_code::UInt32) -> StatusCode.T

Map an HTTP/2 error code to a gRPC status code.

This mapping is per the gRPC HTTP/2 protocol specification:
https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md

# HTTP/2 Error Code Mappings
- NO_ERROR (0x0) → INTERNAL (unexpected for RST_STREAM)
- PROTOCOL_ERROR (0x1) → INTERNAL
- INTERNAL_ERROR (0x2) → INTERNAL
- FLOW_CONTROL_ERROR (0x3) → INTERNAL
- SETTINGS_TIMEOUT (0x4) → INTERNAL
- STREAM_CLOSED (0x5) → INTERNAL
- FRAME_SIZE_ERROR (0x6) → INTERNAL
- REFUSED_STREAM (0x7) → UNAVAILABLE
- CANCEL (0x8) → CANCELLED
- COMPRESSION_ERROR (0x9) → INTERNAL
- CONNECT_ERROR (0xa) → INTERNAL
- ENHANCE_YOUR_CALM (0xb) → RESOURCE_EXHAUSTED
- INADEQUATE_SECURITY (0xc) → PERMISSION_DENIED
- HTTP_1_1_REQUIRED (0xd) → INTERNAL

# Example
```julia
grpc_status = http2_to_grpc_status(0x08)  # CANCEL → CANCELLED
```
"""
function http2_to_grpc_status(http2_error_code::UInt32)::StatusCode.T
    if http2_error_code == _HTTP2_CANCEL
        return StatusCode.CANCELLED
    elseif http2_error_code == _HTTP2_REFUSED_STREAM
        return StatusCode.UNAVAILABLE
    elseif http2_error_code == _HTTP2_ENHANCE_YOUR_CALM
        return StatusCode.RESOURCE_EXHAUSTED
    elseif http2_error_code == _HTTP2_INADEQUATE_SECURITY
        return StatusCode.PERMISSION_DENIED
    else
        # All other HTTP/2 errors map to INTERNAL
        return StatusCode.INTERNAL
    end
end

"""
    http2_to_grpc_status(http2_error_code::Integer) -> StatusCode.T

Convenience method accepting any integer type.
"""
function http2_to_grpc_status(http2_error_code::Integer)::StatusCode.T
    return http2_to_grpc_status(UInt32(http2_error_code))
end
