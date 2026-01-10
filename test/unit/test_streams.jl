# Unit tests for stream types

using Test
using gRPCServer

@testset "Stream Types Unit Tests" begin
    @testset "ServerStream Creation and Send" begin
        messages_sent = []
        closed = Ref(false)

        stream = ServerStream{String}(
            (msg, compress) -> push!(messages_sent, msg),
            () -> closed[] = true
        )

        @test !stream.closed
        @test stream.message_count == 0

        # Send messages
        send!(stream, "Hello")
        @test stream.message_count == 1
        @test messages_sent == ["Hello"]

        send!(stream, "World")
        @test stream.message_count == 2
        @test messages_sent == ["Hello", "World"]

        # Close stream
        close!(stream)
        @test stream.closed
        @test closed[]

        # Cannot send on closed stream
        @test_throws ArgumentError send!(stream, "Error")
    end

    @testset "ServerStream Show" begin
        stream = ServerStream{Int}(
            (msg, compress) -> nothing,
            () -> nothing
        )
        send!(stream, 42)

        str = sprint(show, stream)
        @test occursin("ServerStream", str)
        @test occursin("Int", str)
        @test occursin("messages=1", str)
    end

    @testset "ClientStream Iteration" begin
        messages = ["msg1", "msg2", "msg3"]
        idx = Ref(1)
        cancelled = Ref(false)

        stream = ClientStream{String}(
            () -> begin
                if idx[] > length(messages)
                    return nothing
                end
                msg = messages[idx[]]
                idx[] += 1
                return msg
            end,
            () -> cancelled[]
        )

        @test !stream.finished
        @test stream.message_count == 0

        # Iterate through messages
        collected = String[]
        for msg in stream
            push!(collected, msg)
        end

        @test collected == messages
        @test stream.message_count == 3
        @test stream.finished
    end

    @testset "ClientStream Show" begin
        stream = ClientStream{Float64}(
            () -> nothing,
            () -> false
        )

        str = sprint(show, stream)
        @test occursin("ClientStream", str)
        @test occursin("Float64", str)
    end

    @testset "BidiStream Creation" begin
        received = ["req1", "req2"]
        idx = Ref(1)
        sent = []
        closed = Ref(false)
        cancelled = Ref(false)

        stream = BidiStream{String, String}(
            () -> begin
                if idx[] > length(received)
                    return nothing
                end
                msg = received[idx[]]
                idx[] += 1
                return msg
            end,
            (msg, compress) -> push!(sent, msg),
            () -> closed[] = true,
            () -> cancelled[]
        )

        # Test sending
        send!(stream, "response1")
        @test sent == ["response1"]

        # Test receiving via iteration
        for msg in stream
            send!(stream, "echo: $msg")
        end

        @test length(sent) == 3  # response1 + 2 echoes
    end

    @testset "BidiStream Show" begin
        stream = BidiStream{String, Int}(
            () -> nothing,
            (msg, compress) -> nothing,
            () -> nothing,
            () -> false
        )

        str = sprint(show, stream)
        @test occursin("BidiStream", str)
    end
end
