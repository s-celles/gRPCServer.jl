# Integration tests for metadata handling
# Tests end-to-end metadata round-trip

using Test
using gRPCServer
using Dates

include("test_utils.jl")

@testset "Metadata Integration Tests" begin
    @testset "Request Metadata Access" begin
        received_metadata = Ref{Dict{String, Any}}(Dict())

        handler = (ctx, req) -> begin
            received_metadata[] = Dict(
                "auth" => get_metadata_string(ctx, "authorization"),
                "custom" => get_metadata_string(ctx, "x-custom-header"),
                "binary" => get_metadata_binary(ctx, "x-binary-bin")
            )
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.MetadataService",
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

        # Create context with metadata
        ctx = ServerContext(
            method="/test.MetadataService/Check",
            metadata=Dict{String, Union{String, Vector{UInt8}}}(
                "authorization" => "Bearer token123",
                "x-custom-header" => "custom-value",
                "x-binary-bin" => UInt8[0x01, 0x02, 0x03]
            )
        )
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test received_metadata[]["auth"] == "Bearer token123"
        @test received_metadata[]["custom"] == "custom-value"
        @test received_metadata[]["binary"] == UInt8[0x01, 0x02, 0x03]
    end

    @testset "Response Header Setting" begin
        handler = (ctx, req) -> begin
            set_header!(ctx, "x-response-id", "resp-123")
            set_header!(ctx, "x-timestamp", "2024-01-01T00:00:00Z")
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.HeaderService",
            Dict(
                "SetHeaders" => MethodDescriptor(
                    "SetHeaders",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.HeaderService/SetHeaders")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test ctx.response_headers["x-response-id"] == "resp-123"
        @test ctx.response_headers["x-timestamp"] == "2024-01-01T00:00:00Z"
    end

    @testset "Response Trailer Setting" begin
        handler = (ctx, req) -> begin
            set_trailer!(ctx, "x-processing-time", "150ms")
            set_trailer!(ctx, "x-request-count", "42")
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.TrailerService",
            Dict(
                "SetTrailers" => MethodDescriptor(
                    "SetTrailers",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(method="/test.TrailerService/SetTrailers")
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test ctx.trailers["x-processing-time"] == "150ms"
        @test ctx.trailers["x-request-count"] == "42"
    end

    @testset "Binary Metadata" begin
        handler = (ctx, req) -> begin
            # Read binary metadata
            binary = get_metadata_binary(ctx, "x-proto-bin")
            # Set binary response header
            set_header!(ctx, "x-response-bin", UInt8[0x0A, 0x0B, 0x0C])
            return req
        end

        dispatcher = gRPCServer.RequestDispatcher()
        descriptor = ServiceDescriptor(
            "test.BinaryMetadataService",
            Dict(
                "BinaryTest" => MethodDescriptor(
                    "BinaryTest",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        gRPCServer.register_service!(dispatcher, descriptor)

        ctx = ServerContext(
            method="/test.BinaryMetadataService/BinaryTest",
            metadata=Dict{String, Union{String, Vector{UInt8}}}(
                "x-proto-bin" => UInt8[0x01, 0x02, 0x03]
            )
        )
        request_data = UInt8[0x00, 0x00, 0x00, 0x00, 0x00]

        gRPCServer.dispatch_unary(dispatcher, ctx, request_data)

        @test ctx.response_headers["x-response-bin"] == UInt8[0x0A, 0x0B, 0x0C]
    end

    @testset "Deadline Parsing" begin
        # Test various timeout formats
        test_cases = [
            ("30S", 30.0),      # 30 seconds
            ("5M", 300.0),      # 5 minutes
            ("1H", 3600.0),     # 1 hour
            ("500m", 0.5),      # 500 milliseconds
        ]

        for (timeout_str, expected_seconds) in test_cases
            deadline = gRPCServer.parse_grpc_timeout(timeout_str)
            @test deadline !== nothing

            # Check it's approximately the right time in the future
            remaining = Dates.value(deadline - now()) / 1000.0
            @test remaining > 0
            @test remaining <= expected_seconds + 1  # Allow 1 second tolerance
        end

        # Invalid timeout
        @test gRPCServer.parse_grpc_timeout("") === nothing
        @test gRPCServer.parse_grpc_timeout("invalid") === nothing
    end

    @testset "Remaining Time Calculation" begin
        # Context with deadline
        future_deadline = now() + Second(10)
        ctx = ServerContext(deadline=future_deadline)

        remaining = remaining_time(ctx)
        @test remaining !== nothing
        @test remaining > 0
        @test remaining <= 10.0

        # Context without deadline
        ctx_no_deadline = ServerContext()
        @test remaining_time(ctx_no_deadline) === nothing
    end

    @testset "Context Request ID" begin
        ctx = ServerContext()
        @test ctx.request_id !== nothing
        @test ctx.request_id isa UUID

        # Each context should have unique ID
        ctx2 = ServerContext()
        @test ctx.request_id != ctx2.request_id
    end

    @testset "Peer Info in Context" begin
        peer = PeerInfo(IPv4("192.168.1.100"), 54321)
        ctx = ServerContext(peer=peer)

        @test ctx.peer.address == IPv4("192.168.1.100")
        @test ctx.peer.port == 54321
    end

    @testset "Context Headers Formatting" begin
        ctx = ServerContext()
        set_header!(ctx, "x-string-header", "string-value")
        set_header!(ctx, "x-binary-bin", UInt8[0x01, 0x02])

        headers = gRPCServer.get_response_headers(ctx)

        @test length(headers) == 2
        string_header = findfirst(h -> h[1] == "x-string-header", headers)
        @test string_header !== nothing
        @test headers[string_header][2] == "string-value"
    end

    @testset "Context Trailers Formatting" begin
        ctx = ServerContext()
        set_trailer!(ctx, "x-custom-trailer", "value")

        trailers = gRPCServer.get_response_trailers(ctx, 0, "OK")

        # Should include grpc-status
        status_trailer = findfirst(h -> h[1] == "grpc-status", trailers)
        @test status_trailer !== nothing
        @test trailers[status_trailer][2] == "0"

        # Should include custom trailer
        custom_trailer = findfirst(h -> h[1] == "x-custom-trailer", trailers)
        @test custom_trailer !== nothing
    end

    @testset "Context from Headers" begin
        headers = [
            (":path", "/test.Service/Method"),
            (":authority", "localhost:50051"),
            ("grpc-timeout", "30S"),
            ("authorization", "Bearer token"),
            ("x-custom", "value"),
            ("x-binary-bin", "AQID")  # Base64 encoded [1,2,3]
        ]

        peer = PeerInfo(IPv4("127.0.0.1"), 12345)
        ctx = gRPCServer.create_context_from_headers(headers, peer)

        @test ctx.method == "/test.Service/Method"
        @test ctx.authority == "localhost:50051"
        @test ctx.deadline !== nothing
        @test get_metadata_string(ctx, "authorization") == "Bearer token"
        @test get_metadata_string(ctx, "x-custom") == "value"
    end

    @testset "Metadata with Live Server" begin
        received_auth = Ref{Union{String, Nothing}}(nothing)

        handler = (ctx, req) -> begin
            received_auth[] = get_metadata_string(ctx, "authorization")
            set_header!(ctx, "x-processed", "true")
            return req
        end

        descriptor = ServiceDescriptor(
            "test.LiveMetadataService",
            Dict(
                "Process" => MethodDescriptor(
                    "Process",
                    MethodType.UNARY,
                    "test.Request",
                    "test.Response",
                    handler
                )
            ),
            nothing
        )

        with_test_server() do ts
            gRPCServer.register_service!(ts.server.dispatcher, descriptor)

            @test ts.server.status == ServerStatus.RUNNING

            # Test connection
            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            disconnect!(client)
        end
    end
end
