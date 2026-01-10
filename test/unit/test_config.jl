# Unit tests for ServerConfig and TLSConfig

using Test
using gRPCServer

@testset "Configuration Unit Tests" begin
    @testset "ServerConfig Defaults" begin
        config = ServerConfig()

        # Connection limits
        @test config.max_concurrent_streams == 100

        # Message limits
        @test config.max_message_size == 4 * 1024 * 1024  # 4MB

        # Timeouts
        @test config.keepalive_timeout == 20.0
        @test config.drain_timeout == 30.0

        # TLS
        @test config.tls === nothing

        # Feature toggles
        @test config.enable_health_check == false
        @test config.enable_reflection == false
        @test config.debug_mode == false

        # Compression
        @test config.compression_enabled == true
        @test CompressionCodec.GZIP in config.supported_codecs
    end

    @testset "ServerConfig Custom Values" begin
        config = ServerConfig(
            max_concurrent_streams = 500,
            max_message_size = 16 * 1024 * 1024,
            drain_timeout = 60.0,
            enable_health_check = true,
            enable_reflection = true,
            debug_mode = true
        )

        @test config.max_concurrent_streams == 500
        @test config.max_message_size == 16 * 1024 * 1024
        @test config.drain_timeout == 60.0
        @test config.enable_health_check == true
        @test config.enable_reflection == true
        @test config.debug_mode == true
    end

    @testset "ServerConfig Show Method" begin
        config = ServerConfig(enable_health_check=true)
        str = sprint(show, config)
        @test occursin("ServerConfig", str)
    end

    @testset "TLSConfig Creation" begin
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

    @testset "TLSConfig with mTLS" begin
        tls = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem",
            client_ca = "/path/to/ca.pem",
            require_client_cert = true,
            min_version = :TLSv1_3
        )

        @test tls.client_ca == "/path/to/ca.pem"
        @test tls.require_client_cert == true
        @test tls.min_version == :TLSv1_3
    end

    @testset "ServerStatus Enum" begin
        @test ServerStatus.STOPPED isa ServerStatus.T
        @test ServerStatus.STARTING isa ServerStatus.T
        @test ServerStatus.RUNNING isa ServerStatus.T
        @test ServerStatus.DRAINING isa ServerStatus.T
        @test ServerStatus.STOPPING isa ServerStatus.T

        # All values are distinct
        statuses = [ServerStatus.STOPPED, ServerStatus.STARTING,
                    ServerStatus.RUNNING, ServerStatus.DRAINING,
                    ServerStatus.STOPPING]
        @test length(unique(statuses)) == 5
    end
end
