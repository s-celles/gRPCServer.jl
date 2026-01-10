# Unit tests for ServerContext and PeerInfo

using Test
using gRPCServer
using Sockets
using Dates
using UUIDs

@testset "Context Unit Tests" begin
    @testset "PeerInfo Creation" begin
        peer = PeerInfo(IPv4("127.0.0.1"), 12345)
        @test peer.address == IPv4("127.0.0.1")
        @test peer.port == 12345
        @test peer.certificate === nothing

        # With certificate
        cert = UInt8[0x01, 0x02, 0x03]
        peer_with_cert = PeerInfo(IPv4("192.168.1.1"), 443; certificate=cert)
        @test peer_with_cert.certificate == cert
    end

    @testset "PeerInfo Show" begin
        peer = PeerInfo(IPv4("10.0.0.1"), 8080)
        str = sprint(show, peer)
        @test occursin("PeerInfo", str)
        @test occursin("10.0.0.1", str)

        # With mTLS
        peer_mtls = PeerInfo(IPv4("10.0.0.1"), 8080; certificate=UInt8[1])
        str_mtls = sprint(show, peer_mtls)
        @test occursin("mTLS", str_mtls)
    end

    @testset "ServerContext Creation" begin
        ctx = ServerContext(
            method = "/test.Service/Method",
            authority = "localhost:50051"
        )

        @test ctx.method == "/test.Service/Method"
        @test ctx.authority == "localhost:50051"
        @test ctx.request_id isa UUID
        @test !ctx.cancelled
        @test ctx.deadline === nothing
        @test isempty(ctx.metadata)
        @test isempty(ctx.response_headers)
        @test isempty(ctx.trailers)
    end

    @testset "ServerContext Metadata" begin
        metadata = Dict{String, Union{String, Vector{UInt8}}}(
            "authorization" => "Bearer token123",
            "x-custom-bin" => UInt8[0x01, 0x02]
        )
        ctx = ServerContext(method="/test", metadata=metadata)

        # get_metadata
        @test get_metadata(ctx, "authorization") == "Bearer token123"
        @test get_metadata(ctx, "x-custom-bin") == UInt8[0x01, 0x02]
        @test get_metadata(ctx, "nonexistent") === nothing

        # get_metadata_string
        @test get_metadata_string(ctx, "authorization") == "Bearer token123"
        @test get_metadata_string(ctx, "x-custom-bin") === nothing  # binary returns nothing

        # get_metadata_binary
        @test get_metadata_binary(ctx, "x-custom-bin") == UInt8[0x01, 0x02]
    end

    @testset "ServerContext Headers and Trailers" begin
        ctx = ServerContext()

        # Set response headers
        set_header!(ctx, "X-Request-Id", "abc123")
        set_header!(ctx, "x-binary-bin", UInt8[0x01, 0x02])

        @test haskey(ctx.response_headers, "x-request-id")
        @test haskey(ctx.response_headers, "x-binary-bin")

        # Set trailers
        set_trailer!(ctx, "x-processing-time", "50ms")
        @test haskey(ctx.trailers, "x-processing-time")
    end

    @testset "ServerContext Deadline" begin
        # No deadline
        ctx_no_deadline = ServerContext()
        @test remaining_time(ctx_no_deadline) === nothing

        # With deadline in the future
        future_deadline = now() + Second(30)
        ctx_future = ServerContext(deadline=future_deadline)
        remaining = remaining_time(ctx_future)
        @test remaining !== nothing
        @test remaining > 0
        @test remaining <= 30.0

        # With deadline in the past
        past_deadline = now() - Second(10)
        ctx_past = ServerContext(deadline=past_deadline)
        remaining_past = remaining_time(ctx_past)
        @test remaining_past !== nothing
        @test remaining_past < 0
    end

    @testset "ServerContext Cancellation" begin
        ctx = ServerContext()
        @test !is_cancelled(ctx)

        # Cancel the context
        ctx.cancelled = true
        @test is_cancelled(ctx)
    end

    @testset "ServerContext Show" begin
        ctx = ServerContext(method="/test.Service/Method")
        str = sprint(show, ctx)
        @test occursin("ServerContext", str)
    end
end
