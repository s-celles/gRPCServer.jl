# Unit tests for TLS configuration

using Test
using gRPCServer

@testset "TLS Configuration Unit Tests" begin
    @testset "TLSConfig Creation" begin
        # Create a TLSConfig with basic parameters
        config = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key"
        )

        @test config.cert_chain == "/path/to/server.crt"
        @test config.private_key == "/path/to/server.key"
        @test config.client_ca === nothing
        @test config.require_client_cert == false
        @test config.min_version == :TLSv1_2
    end

    @testset "TLSConfig with mTLS" begin
        config = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key",
            client_ca = "/path/to/ca.crt",
            require_client_cert = true
        )

        @test config.client_ca == "/path/to/ca.crt"
        @test config.require_client_cert == true
    end

    @testset "TLSConfig TLS Version" begin
        # TLS 1.2 (default)
        config_12 = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key",
            min_version = :TLSv1_2
        )
        @test config_12.min_version == :TLSv1_2

        # TLS 1.3
        config_13 = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key",
            min_version = :TLSv1_3
        )
        @test config_13.min_version == :TLSv1_3

        # Invalid version should throw
        @test_throws ArgumentError TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key",
            min_version = :TLSv1_0
        )
    end

    @testset "ALPN Protocols" begin
        @test gRPCServer.ALPN_PROTOCOLS == ["h2"]
    end

    @testset "CertificateWatcher Creation" begin
        config = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key"
        )

        reload_called = Ref(false)
        watcher = gRPCServer.CertificateWatcher(config, () -> reload_called[] = true)

        @test watcher.config === config
        @test watcher.watching == false
        @test isempty(watcher.last_modified)
    end

    @testset "verify_tls_config with missing files" begin
        config = TLSConfig(
            cert_chain = "/nonexistent/server.crt",
            private_key = "/nonexistent/server.key"
        )

        # Should return false for missing files
        @test gRPCServer.verify_tls_config(config) == false
    end

    @testset "Server with TLS Configuration" begin
        config = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key"
        )

        server = GRPCServer("0.0.0.0", 50051; tls = config)
        @test server.config.tls === config
    end
end
