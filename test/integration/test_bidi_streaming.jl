# Integration tests for bidirectional streaming RPC
# Tests end-to-end bidirectional streaming handling

using Test
using gRPCServer

include("test_utils.jl")

@testset "Bidirectional Streaming RPC Integration Tests" begin
    @testset "Bidi Streaming Method Resolution" begin
        dispatcher = gRPCServer.RequestDispatcher()

        handler = (ctx, stream) -> begin
            for msg in stream
                send!(stream, msg)  # Echo back
            end
            return nothing
        end

        descriptor = ServiceDescriptor(
            "test.BidiService",
            Dict(
                "Echo" => MethodDescriptor(
                    "Echo",
                    MethodType.BIDI_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        result = gRPCServer.lookup_method(dispatcher.registry, "/test.BidiService/Echo")
        @test result !== nothing
        svc, method = result
        @test method.method_type == MethodType.BIDI_STREAMING
    end

    @testset "BidiStream Creation" begin
        messages = [UInt8[0x01], UInt8[0x02], nothing]
        idx = Ref(1)
        sent_messages = Vector{UInt8}[]
        closed = Ref(false)

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        send_callback = (msg, compress) -> push!(sent_messages, msg)
        close_callback = () -> closed[] = true
        is_cancelled_callback = () -> false

        stream = gRPCServer.BidiStream{Vector{UInt8}, Vector{UInt8}}(
            receive_callback, send_callback, close_callback, is_cancelled_callback
        )

        # Iterate and echo
        for msg in stream
            send!(stream, msg)
        end

        @test length(sent_messages) == 2
        @test sent_messages[1] == UInt8[0x01]
        @test sent_messages[2] == UInt8[0x02]
    end

    @testset "BidiStream Input/Output Tracking" begin
        messages = [UInt8[0x01], UInt8[0x02], UInt8[0x03], nothing]
        idx = Ref(1)
        sent_count = Ref(0)

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        send_callback = (msg, compress) -> sent_count[] += 1
        close_callback = () -> nothing
        is_cancelled_callback = () -> false

        stream = gRPCServer.BidiStream{Vector{UInt8}, Vector{UInt8}}(
            receive_callback, send_callback, close_callback, is_cancelled_callback
        )

        # Read all inputs
        for msg in stream
            # Process
        end

        # Send some outputs
        send!(stream, UInt8[0x0A])
        send!(stream, UInt8[0x0B])

        @test gRPCServer.is_input_finished(stream)
        @test stream.input.message_count == 3
        @test stream.output.message_count == 2
        @test sent_count[] == 2
    end

    @testset "BidiStream Close" begin
        messages = [nothing]
        idx = Ref(1)
        closed = Ref(false)

        receive_callback = () -> nothing
        send_callback = (msg, compress) -> nothing
        close_callback = () -> closed[] = true
        is_cancelled_callback = () -> false

        stream = gRPCServer.BidiStream{Vector{UInt8}, Vector{UInt8}}(
            receive_callback, send_callback, close_callback, is_cancelled_callback
        )

        @test !gRPCServer.is_output_closed(stream)
        close!(stream)
        @test gRPCServer.is_output_closed(stream)
        @test closed[]
    end

    @testset "Bidi Streaming Dispatch" begin
        messages = [UInt8[0x01], UInt8[0x02], nothing]
        idx = Ref(1)
        sent_messages = Vector{UInt8}[]

        handler = (ctx, stream) -> begin
            for msg in stream
                # Double each byte and send back
                doubled = UInt8[b * 2 for b in msg]
                send!(stream, doubled)
            end
            return nothing
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.BidiService",
            Dict(
                "Double" => MethodDescriptor(
                    "Double",
                    MethodType.BIDI_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.BidiService/Double")

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        send_callback = (msg, compress) -> push!(sent_messages, msg)
        close_callback = () -> nothing
        is_cancelled_callback = () -> false

        status, message = gRPCServer.dispatch_bidi_streaming(
            dispatcher, ctx, receive_callback, send_callback, close_callback, is_cancelled_callback
        )

        @test status == StatusCode.OK
        @test length(sent_messages) == 2
        @test sent_messages[1] == UInt8[0x02]  # 0x01 * 2
        @test sent_messages[2] == UInt8[0x04]  # 0x02 * 2
    end

    @testset "Bidi Streaming Error Handling" begin
        messages = [UInt8[0x01], UInt8[0x02], nothing]
        idx = Ref(1)
        sent_messages = Vector{UInt8}[]

        handler = (ctx, stream) -> begin
            count = 0
            for msg in stream
                count += 1
                if count == 2
                    throw(GRPCError(StatusCode.ABORTED, "Processing aborted"))
                end
                send!(stream, msg)
            end
            return nothing
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.ErrorBidiService",
            Dict(
                "FailAfterTwo" => MethodDescriptor(
                    "FailAfterTwo",
                    MethodType.BIDI_STREAMING,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.ErrorBidiService/FailAfterTwo")

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        send_callback = (msg, compress) -> push!(sent_messages, msg)
        close_callback = () -> nothing
        is_cancelled_callback = () -> false

        status, message = gRPCServer.dispatch_bidi_streaming(
            dispatcher, ctx, receive_callback, send_callback, close_callback, is_cancelled_callback
        )

        @test status == StatusCode.ABORTED
        @test length(sent_messages) == 1  # Only first message echoed
    end

    @testset "Bidi Streaming Cancellation" begin
        messages = [UInt8[0x01], UInt8[0x02], UInt8[0x03], nothing]
        idx = Ref(1)
        cancelled = Ref(false)
        sent_messages = Vector{UInt8}[]

        receive_callback = () -> begin
            if idx[] > length(messages)
                return nothing
            end
            msg = messages[idx[]]
            idx[] += 1
            return msg
        end
        send_callback = (msg, compress) -> push!(sent_messages, msg)
        close_callback = () -> nothing
        is_cancelled_callback = () -> cancelled[]

        stream = gRPCServer.BidiStream{Vector{UInt8}, Vector{UInt8}}(
            receive_callback, send_callback, close_callback, is_cancelled_callback
        )

        # Process with cancellation
        try
            for msg in stream
                send!(stream, msg)
                if length(sent_messages) == 2
                    cancelled[] = true
                end
            end
        catch e
            @test e isa StreamCancelledError
        end

        @test gRPCServer.is_cancelled(stream)
    end

    @testset "Bidi Streaming with Live Server" begin
        handler = (ctx, stream) -> begin
            for msg in stream
                send!(stream, msg)
            end
            return nothing
        end

        descriptor = ServiceDescriptor(
            "test.LiveBidiService",
            Dict(
                "Echo" => MethodDescriptor(
                    "Echo",
                    MethodType.BIDI_STREAMING,
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
                "/test.LiveBidiService/Echo"
            ) !== nothing

            @test ts.server.status == ServerStatus.RUNNING
        end
    end
end
