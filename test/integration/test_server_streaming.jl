# Integration tests for server streaming RPC
# Tests end-to-end server streaming handling

using Test
using gRPCServer

# TestUtils is included once in runtests.jl to avoid method redefinition warnings
# using TestUtils is inherited from the parent module

@testset "Server Streaming RPC Integration Tests" begin
    @testset "Server Streaming Method Resolution" begin
        dispatcher = gRPCServer.RequestDispatcher()

        handler = (ctx, req, stream) -> begin
            for i in 1:3
                send!(stream, UInt8[UInt8(i)])
            end
            return nothing
        end

        descriptor = ServiceDescriptor(
            "test.StreamService",
            Dict(
                "StreamMethod" => MethodDescriptor(
                    "StreamMethod",
                    MethodType.SERVER_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        result = gRPCServer.lookup_method(dispatcher.registry, "/test.StreamService/StreamMethod")
        @test result !== nothing
        svc, method = result
        @test method.method_type == MethodType.SERVER_STREAMING
    end

    @testset "Server Stream Send" begin
        messages_sent = Int[]
        send_callback = (msg, compress) -> push!(messages_sent, length(msg))
        close_callback = () -> nothing

        stream = gRPCServer.ServerStream{Vector{UInt8}}(send_callback, close_callback)

        # Send messages
        send!(stream, UInt8[0x01])
        send!(stream, UInt8[0x02, 0x03])
        send!(stream, UInt8[0x04, 0x05, 0x06])

        @test length(messages_sent) == 3
        @test messages_sent == [1, 2, 3]
        @test stream.message_count == 3
    end

    @testset "Server Stream Close" begin
        closed = Ref(false)
        close_callback = () -> closed[] = true
        send_callback = (msg, compress) -> nothing

        stream = gRPCServer.ServerStream{Vector{UInt8}}(send_callback, close_callback)

        @test !gRPCServer.is_closed(stream)
        close!(stream)
        @test gRPCServer.is_closed(stream)
        @test closed[]

        # Cannot send after close
        @test_throws ArgumentError send!(stream, UInt8[0x01])
    end

    @testset "Server Streaming Dispatch" begin
        messages_sent = Vector{UInt8}[]

        handler = (ctx, req, stream) -> begin
            for i in 1:5
                send!(stream, UInt8[UInt8(i)])
            end
            return nothing
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.StreamService",
            Dict(
                "Generate" => MethodDescriptor(
                    "Generate",
                    MethodType.SERVER_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.StreamService/Generate")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]  # Empty message

        send_callback = (msg, compress) -> push!(messages_sent, msg)
        close_callback = () -> nothing

        status, message = gRPCServer.dispatch_server_streaming(
            dispatcher, ctx, request_data, send_callback, close_callback
        )

        @test status == StatusCode.OK
        @test length(messages_sent) == 5
    end

    @testset "Server Streaming Error Handling" begin
        handler = (ctx, req, stream) -> begin
            send!(stream, UInt8[0x01])
            throw(GRPCError(StatusCode.INTERNAL, "Stream error"))
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.ErrorStreamService",
            Dict(
                "FailStream" => MethodDescriptor(
                    "FailStream",
                    MethodType.SERVER_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ErrorStreamService/FailStream")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        messages_sent = Vector{UInt8}[]
        send_callback = (msg, compress) -> push!(messages_sent, msg)
        close_callback = () -> nothing

        status, message = gRPCServer.dispatch_server_streaming(
            dispatcher, ctx, request_data, send_callback, close_callback
        )

        @test status == StatusCode.INTERNAL
        @test length(messages_sent) == 1  # One message before error
    end

    @testset "Server Streaming with Live Server" begin
        messages_received = Int[]

        handler = (ctx, req, stream) -> begin
            for i in 1:3
                send!(stream, UInt8[UInt8(i)])
            end
            return nothing
        end

        descriptor = ServiceDescriptor(
            "test.LiveStreamService",
            Dict(
                "Stream" => MethodDescriptor(
                    "Stream",
                    MethodType.SERVER_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        with_test_server() do ts
            gRPCServer.register_service!(ts.server.dispatcher, descriptor)

            # Verify service registered
            @test gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/test.LiveStreamService/Stream"
            ) !== nothing

            # Verify server is running
            @test ts.server.status == ServerStatus.RUNNING
        end
    end
end
