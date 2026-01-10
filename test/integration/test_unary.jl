# Integration tests for unary RPC
# Tests end-to-end unary RPC handling

using Test
using gRPCServer
using Sockets

include("test_utils.jl")

@testset "Unary RPC Integration Tests" begin
    @testset "Basic Connection" begin
        with_test_server() do ts
            # Test basic connection
            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            @test is_connected(client)
            disconnect!(client)
            @test !is_connected(client)
        end
    end

    @testset "Multiple Concurrent Connections" begin
        with_test_server(max_concurrent_streams=100) do ts
            clients = [MockGRPCClient("127.0.0.1", ts.port) for _ in 1:10]

            # Connect all clients
            for client in clients
                @test connect!(client)
            end

            # All should be connected
            @test all(is_connected, clients)

            # Disconnect all
            for client in clients
                disconnect!(client)
            end
        end
    end

    @testset "Server with Registered Service" begin
        # Create a test service
        handler = (ctx, req) -> req
        descriptor = ServiceDescriptor(
            "test.EchoService",
            Dict(
                "Echo" => MethodDescriptor(
                    "Echo",
                    MethodType.UNARY,
                    "test.EchoRequest",
                    "test.EchoResponse",
                    handler
                )
            ),
            nothing
        )

        with_test_server() do ts
            # Register service
            gRPCServer.register_service!(ts.server.dispatcher, descriptor)
            ts.server.health_status["test.EchoService"] = HealthStatus.SERVING

            # Verify service is registered
            @test "test.EchoService" in services(ts.server)

            # Test connection
            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            disconnect!(client)
        end
    end

    @testset "Unary Method Resolution" begin
        # Test that the dispatcher correctly resolves unary methods
        dispatcher = gRPCServer.RequestDispatcher()

        handler = (ctx, req) -> "response"
        descriptor = ServiceDescriptor(
            "test.TestService",
            Dict(
                "TestMethod" => MethodDescriptor(
                    "TestMethod",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        # Test lookup
        result = gRPCServer.lookup_method(dispatcher.registry, "/test.TestService/TestMethod")
        @test result !== nothing
        svc, method = result
        @test svc.name == "test.TestService"
        @test method.name == "TestMethod"
        @test method.method_type == MethodType.UNARY

        # Unknown method returns nothing
        @test gRPCServer.lookup_method(dispatcher.registry, "/test.TestService/Unknown") === nothing
    end

    @testset "Unary Dispatch with Context" begin
        # Test that context is properly created and passed to handlers
        received_ctx = Ref{Union{ServerContext, Nothing}}(nothing)
        received_req = Ref{Any}(nothing)

        handler = (ctx, req) -> begin
            received_ctx[] = ctx
            received_req[] = req
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.ContextService",
            Dict(
                "Check" => MethodDescriptor(
                    "Check",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        # Create context and dispatch
        ctx = ServerContext(method="/test.ContextService/Check")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03]  # gRPC message

        status, message, response = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        # Handler should have been called
        @test received_ctx[] !== nothing
        @test received_ctx[].method == "/test.ContextService/Check"
        @test received_req[] !== nothing
    end

    @testset "Unary Error Handling" begin
        dispatcher = gRPCServer.RequestDispatcher()

        # Handler that throws GRPCError
        error_handler = (ctx, req) -> begin
            throw(GRPCError(StatusCode.NOT_FOUND, "Resource not found"))
        end

        descriptor = ServiceDescriptor(
            "test.ErrorService",
            Dict(
                "Fail" => MethodDescriptor(
                    "Fail",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    error_handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ErrorService/Fail")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03]

        status, message, response = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test status == StatusCode.NOT_FOUND
        @test message == "Resource not found"
    end

    @testset "Unary UNIMPLEMENTED for Unknown Method" begin
        dispatcher = gRPCServer.RequestDispatcher()

        ctx = ServerContext(method="/unknown.Service/Method")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03]

        status, message, response = gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test status == StatusCode.UNIMPLEMENTED
        @test occursin("unknown.Service", message) || occursin("not found", lowercase(message))
    end

    @testset "gRPC Message Format" begin
        # Test building gRPC messages
        data = UInt8[0x01, 0x02, 0x03, 0x04, 0x05]
        msg = build_grpc_message(data)

        @test length(msg) == 5 + 5  # 5 byte header + 5 byte data
        @test msg[1] == 0x00  # Not compressed
        @test msg[6:end] == data

        # Test parsing
        compressed, parsed = parse_grpc_message(msg)
        @test !compressed
        @test parsed == data

        # Test compressed flag
        msg_compressed = build_grpc_message(data; compressed=true)
        @test msg_compressed[1] == 0x01
    end

    @testset "Server Status During Operations" begin
        with_test_server() do ts
            @test ts.server.status == ServerStatus.RUNNING

            # Connect and verify server still running
            client = MockGRPCClient("127.0.0.1", ts.port)
            connect!(client)
            @test ts.server.status == ServerStatus.RUNNING
            disconnect!(client)
        end
    end
end
