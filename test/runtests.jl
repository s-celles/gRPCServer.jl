using Test
using gRPCServer

# Include TestUtils module once for all tests to avoid method redefinition warnings
include("TestUtils.jl")
using .TestUtils

@testset "gRPCServer.jl" begin
    # Aqua.jl quality checks
    include("aqua.jl")

    # Unit tests
    include("unit/test_config.jl")
    include("unit/test_errors.jl")
    include("unit/test_context.jl")
    include("unit/test_streams.jl")
    include("unit/test_interceptors.jl")
    include("unit/test_dispatch.jl")
    include("unit/test_compression.jl")
    include("unit/test_health.jl")
    include("unit/test_server.jl")
    include("unit/test_tls.jl")
    include("unit/test_reflection.jl")
    include("unit/test_hpack.jl")

    # Integration tests
    include("integration/test_unary.jl")
    include("integration/test_server_streaming.jl")
    include("integration/test_client_streaming.jl")
    include("integration/test_bidi_streaming.jl")
    include("integration/test_errors.jl")
    include("integration/test_metadata.jl")
    include("integration/test_interceptors.jl")
    include("integration/test_health.jl")
    include("integration/test_tls.jl")

    # Contract tests
    include("contract/test_grpcurl.jl")

    # Basic module tests
    @testset "Module loads correctly" begin
        @test isdefined(gRPCServer, :GRPCServer)
        @test isdefined(gRPCServer, :ServerConfig)
        @test isdefined(gRPCServer, :TLSConfig)
        @test isdefined(gRPCServer, :ServerContext)
        @test isdefined(gRPCServer, :ServiceDescriptor)
        @test isdefined(gRPCServer, :MethodDescriptor)
    end

    @testset "Enumerations" begin
        @test ServerStatus.STOPPED isa ServerStatus.T
        @test ServerStatus.RUNNING isa ServerStatus.T
        @test StatusCode.OK isa StatusCode.T
        @test StatusCode.INTERNAL isa StatusCode.T
        @test MethodType.UNARY isa MethodType.T
        @test MethodType.BIDI_STREAMING isa MethodType.T
        @test HealthStatus.SERVING isa HealthStatus.T
        @test CompressionCodec.GZIP isa CompressionCodec.T
    end

    @testset "ServerConfig" begin
        config = ServerConfig()
        @test config.max_message_size == 4 * 1024 * 1024
        @test config.max_concurrent_streams == 100
        @test config.enable_health_check == false
        @test config.debug_mode == false
    end

    @testset "TLSConfig" begin
        tls = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem"
        )
        @test tls.cert_chain == "/path/to/cert.pem"
        @test tls.private_key == "/path/to/key.pem"
        @test tls.client_ca === nothing
        @test tls.require_client_cert == false
        @test tls.min_version == :TLSv1_2
    end

    @testset "GRPCError" begin
        err = GRPCError(StatusCode.NOT_FOUND, "Resource not found")
        @test err.code == StatusCode.NOT_FOUND
        @test err.message == "Resource not found"
        @test isempty(err.details)
    end

    @testset "Compression" begin
        @test codec_name(CompressionCodec.GZIP) == "gzip"
        @test codec_name(CompressionCodec.DEFLATE) == "deflate"
        @test codec_name(CompressionCodec.IDENTITY) == "identity"

        @test parse_codec("gzip") == CompressionCodec.GZIP
        @test parse_codec("deflate") == CompressionCodec.DEFLATE
        @test parse_codec("identity") == CompressionCodec.IDENTITY
        @test parse_codec("unknown") === nothing

        # Test compress/decompress round-trip
        data = Vector{UInt8}("Hello, gRPC!")
        compressed = compress(data, CompressionCodec.GZIP)
        decompressed = decompress(compressed, CompressionCodec.GZIP)
        @test decompressed == data
    end

    @testset "GRPCServer creation" begin
        server = GRPCServer("0.0.0.0", 50051)
        @test server.host == "0.0.0.0"
        @test server.port == 50051
        @test server.status == ServerStatus.STOPPED
        @test isempty(services(server))
    end

    @testset "GRPCServer with config" begin
        server = GRPCServer(
            "localhost", 8080;
            max_message_size = 8 * 1024 * 1024,
            enable_health_check = true,
            debug_mode = true
        )
        @test server.port == 8080
        @test server.config.max_message_size == 8 * 1024 * 1024
        @test server.config.enable_health_check == true
        @test server.config.debug_mode == true
    end
end
