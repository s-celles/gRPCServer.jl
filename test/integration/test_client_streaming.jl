# Integration tests for client streaming RPC
# Tests end-to-end client streaming handling

using Test
using gRPCServer

include("test_utils.jl")

@testset "Client Streaming RPC Integration Tests" begin
    @testset "Client Streaming Method Resolution" begin
        dispatcher = gRPCServer.RequestDispatcher()

        handler = (ctx, stream) -> begin
            count = 0
            for msg in stream
                count += 1
            end
            return UInt8[UInt8(count)]
        end

        descriptor = ServiceDescriptor(
            "test.ClientStreamService",
            Dict(
                "Collect" => MethodDescriptor(
                    "Collect",
                    MethodType.CLIENT_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        result = gRPCServer.lookup_method(dispatcher.registry, "/test.ClientStreamService/Collect")
        @test result !== nothing
        svc, method = result
        @test method.method_type == MethodType.CLIENT_STREAMING
    end

    @testset "Client Stream Iterator" begin
        messages = [UInt8[0x01], UInt8[0x02], UInt8[0x03], nothing]
        idx = Ref(1)

        receive_callback = () -> begin
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        is_cancelled_callback = () -> false

        stream = gRPCServer.ClientStream{Vector{UInt8}}(receive_callback, is_cancelled_callback)

        # Iterate through stream
        received = Vector{UInt8}[]
        for msg in stream
            push!(received, msg)
        end

        @test length(received) == 3
        @test received[1] == UInt8[0x01]
        @test received[2] == UInt8[0x02]
        @test received[3] == UInt8[0x03]
        @test gRPCServer.is_finished(stream)
    end

    @testset "Client Stream Cancellation" begin
        messages = [UInt8[0x01], UInt8[0x02], UInt8[0x03]]
        idx = Ref(1)
        cancelled = Ref(false)

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        is_cancelled_callback = () -> cancelled[]

        stream = gRPCServer.ClientStream{Vector{UInt8}}(receive_callback, is_cancelled_callback)

        # Start iterating then cancel
        received = Vector{UInt8}[]
        try
            for msg in stream
                push!(received, msg)
                if length(received) == 2
                    cancelled[] = true
                end
            end
        catch e
            @test e isa StreamCancelledError
        end

        @test length(received) == 2
    end

    @testset "Client Streaming Dispatch" begin
        messages = [UInt8[0x01], UInt8[0x02], UInt8[0x03], nothing]
        idx = Ref(1)

        handler = (ctx, stream) -> begin
            total = 0
            for msg in stream
                total += length(msg)
            end
            return UInt8[UInt8(total)]
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.ClientStreamService",
            Dict(
                "Sum" => MethodDescriptor(
                    "Sum",
                    MethodType.CLIENT_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ClientStreamService/Sum")

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        is_cancelled_callback = () -> false

        status, message, response = gRPCServer.dispatch_client_streaming(
            dispatcher, ctx, receive_callback, is_cancelled_callback
        )

        @test status == StatusCode.OK
    end

    @testset "Client Streaming Error Handling" begin
        messages = [UInt8[0x01], nothing]
        idx = Ref(1)

        handler = (ctx, stream) -> begin
            for msg in stream
                throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Bad message"))
            end
            return UInt8[]
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.ErrorClientStreamService",
            Dict(
                "FailProcess" => MethodDescriptor(
                    "FailProcess",
                    MethodType.CLIENT_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ErrorClientStreamService/FailProcess")

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        is_cancelled_callback = () -> false

        status, message, response = gRPCServer.dispatch_client_streaming(
            dispatcher, ctx, receive_callback, is_cancelled_callback
        )

        @test status == StatusCode.INVALID_ARGUMENT
    end

    @testset "Client Stream Message Count" begin
        messages = [UInt8[0x01], UInt8[0x02], UInt8[0x03], UInt8[0x04], UInt8[0x05], nothing]
        idx = Ref(1)

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        is_cancelled_callback = () -> false

        stream = gRPCServer.ClientStream{Vector{UInt8}}(receive_callback, is_cancelled_callback)

        count = 0
        for _ in stream
            count += 1
        end

        @test count == 5
        @test stream.message_count == 5
    end

    @testset "Client Streaming with Live Server" begin
        handler = (ctx, stream) -> begin
            count = 0
            for msg in stream
                count += 1
            end
            return UInt8[UInt8(count)]
        end

        descriptor = ServiceDescriptor(
            "test.LiveClientStreamService",
            Dict(
                "Count" => MethodDescriptor(
                    "Count",
                    MethodType.CLIENT_STREAMING,
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
                "/test.LiveClientStreamService/Count"
            ) !== nothing

            @test ts.server.status == ServerStatus.RUNNING
        end
    end
end
