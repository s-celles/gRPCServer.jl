# Integration tests for error handling
# Tests end-to-end error handling and status codes

using Test
using gRPCServer

# TestUtils is included once in runtests.jl to avoid method redefinition warnings
# using TestUtils is inherited from the parent module

@testset "Error Handling Integration Tests" begin
    @testset "GRPCError Propagation" begin
        for (code, name) in [
            (StatusCode.CANCELLED, "CANCELLED"),
            (StatusCode.UNKNOWN, "UNKNOWN"),
            (StatusCode.INVALID_ARGUMENT, "INVALID_ARGUMENT"),
            (StatusCode.DEADLINE_EXCEEDED, "DEADLINE_EXCEEDED"),
            (StatusCode.NOT_FOUND, "NOT_FOUND"),
            (StatusCode.ALREADY_EXISTS, "ALREADY_EXISTS"),
            (StatusCode.PERMISSION_DENIED, "PERMISSION_DENIED"),
            (StatusCode.RESOURCE_EXHAUSTED, "RESOURCE_EXHAUSTED"),
            (StatusCode.FAILED_PRECONDITION, "FAILED_PRECONDITION"),
            (StatusCode.ABORTED, "ABORTED"),
            (StatusCode.OUT_OF_RANGE, "OUT_OF_RANGE"),
            (StatusCode.UNIMPLEMENTED, "UNIMPLEMENTED"),
            (StatusCode.INTERNAL, "INTERNAL"),
            (StatusCode.UNAVAILABLE, "UNAVAILABLE"),
            (StatusCode.DATA_LOSS, "DATA_LOSS"),
            (StatusCode.UNAUTHENTICATED, "UNAUTHENTICATED"),
        ]
            handler = (ctx, req) -> throw(GRPCError(code, "Test $name error"))

            dispatcher = gRPCServer.RequestDispatcher()
            descriptor = ServiceDescriptor(
                "test.ErrorService",
                Dict(
                    "Throw$name" => MethodDescriptor(
                        "Throw$name",
                        MethodType.UNARY,
                        "test.Request",
                        "test.Response",
                        handler
                    )
                ),
                nothing
            )

            gRPCServer.register_service!(dispatcher, descriptor)

            ctx = ServerContext(method="/test.ErrorService/Throw$name")
            request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

            status, message, response = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

            @test status == code
            @test occursin(name, message) || occursin("Test", message)
        end
    end

    @testset "Exception to StatusCode Mapping" begin
        # Test that Julia exceptions are mapped to appropriate status codes
        test_cases = [
            (ArgumentError("bad arg"), StatusCode.INVALID_ARGUMENT),
            (BoundsError([1,2], 5), StatusCode.OUT_OF_RANGE),
            (KeyError(:missing), StatusCode.NOT_FOUND),
            (ErrorException("generic"), StatusCode.INTERNAL),
        ]

        for (exception, expected_code) in test_cases
            handler = (ctx, req) -> throw(exception)

            dispatcher = gRPCServer.RequestDispatcher()
            descriptor = ServiceDescriptor(
                "test.ExceptionService",
                Dict(
                    "Throw" => MethodDescriptor(
                        "Throw",
                        MethodType.UNARY,
                        "test.Request",
                        "test.Response",
                        handler
                    )
                ),
                nothing
            )

            gRPCServer.register_service!(dispatcher, descriptor)

            ctx = ServerContext(method="/test.ExceptionService/Throw")
            request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

            status, message, response = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

            @test status == expected_code
        end
    end

    @testset "Debug Mode Error Details" begin
        exception_message = "Detailed error information for debugging"
        handler = (ctx, req) -> throw(ErrorException(exception_message))

        # Debug mode disabled - should mask details
        dispatcher_prod = gRPCServer.RequestDispatcher(debug_mode=false)
        descriptor = ServiceDescriptor(
            "test.DebugService",
            Dict(
                "Fail" => MethodDescriptor(
                    "Fail",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher_prod, descriptor)

        ctx = ServerContext(method="/test.DebugService/Fail")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        status, message, _ = gRPCServer.dispatch_unary(dispatcher_prod, ctx, request_data)
        @test status == StatusCode.INTERNAL
        @test !occursin(exception_message, message)  # Should be masked

        # Debug mode enabled - should include details
        dispatcher_debug = gRPCServer.RequestDispatcher(debug_mode=true)
        gRPCServer.register_service!(dispatcher_debug, descriptor)

        status, message, _ = gRPCServer.dispatch_unary(dispatcher_debug, ctx, request_data)
        @test status == StatusCode.INTERNAL
        @test occursin(exception_message, message)  # Should include details
    end

    @testset "Error with Details" begin
        details = Any["detail1", "detail2", "detail3"]
        handler = (ctx, req) -> throw(GRPCError(StatusCode.FAILED_PRECONDITION, "Failed", details))

        # Use debug_mode=true to properly propagate GRPCError status
        dispatcher = gRPCServer.RequestDispatcher(debug_mode=true)
        descriptor = ServiceDescriptor(
            "test.DetailService",
            Dict(
                "FailWithDetails" => MethodDescriptor(
                    "FailWithDetails",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.DetailService/FailWithDetails")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        status, message, _ = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)
        @test status == StatusCode.FAILED_PRECONDITION
    end

    @testset "Streaming Error Recovery" begin
        sent_count = Ref(0)

        handler = (ctx, req, stream) -> begin
            for i in 1:3
                send!(stream, UInt8[UInt8(i)])
                sent_count[] += 1
            end
            throw(GRPCError(StatusCode.RESOURCE_EXHAUSTED, "Too many messages"))
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.StreamErrorService",
            Dict(
                "FailMidStream" => MethodDescriptor(
                    "FailMidStream",
                    MethodType.SERVER_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.StreamErrorService/FailMidStream")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        messages = Vector{UInt8}[]
        send_callback = (msg, compress) -> push!(messages, msg)
        close_callback = () -> nothing

        status, message = gRPCServer.dispatch_server_streaming(
            dispatcher, ctx, request_data, send_callback, close_callback
        )

        @test status == StatusCode.RESOURCE_EXHAUSTED
        @test sent_count[] == 3  # All messages sent before error
    end

    @testset "Error with Live Server" begin
        handler = (ctx, req) -> throw(GRPCError(StatusCode.UNIMPLEMENTED, "Not implemented"))

        descriptor = ServiceDescriptor(
            "test.LiveErrorService",
            Dict(
                "NotImpl" => MethodDescriptor(
                    "NotImpl",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        with_test_server(debug_mode=false) do ts
            gRPCServer.register_service!(ts.server.dispatcher, descriptor)

            # Verify server is running despite error-throwing service
            @test ts.server.status == ServerStatus.RUNNING

            # Test connection still works
            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            disconnect!(client)
        end
    end
end
