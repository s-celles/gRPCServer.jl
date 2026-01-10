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
