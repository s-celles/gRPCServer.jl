# Integration tests for TLS configuration
# Tests TLS/mTLS setup and configuration

using Test
using gRPCServer
using Sockets

# TestUtils is included once in runtests.jl to avoid method redefinition warnings
# using TestUtils is inherited from the parent module

@testset "TLS Integration Tests" begin
    @testset "TLSConfig Creation" begin
        # Basic TLS config
        config = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem"
        )

        @test config.cert_chain == "/path/to/cert.pem"
        @test config.private_key == "/path/to/key.pem"
        @test config.client_ca === nothing
        @test config.require_client_cert == false
        @test config.min_version == :TLSv1_2
    end

    @testset "TLSConfig with mTLS" begin
        config = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem",
            client_ca = "/path/to/ca.pem",
            require_client_cert = true
        )

        @test config.client_ca == "/path/to/ca.pem"
        @test config.require_client_cert == true
    end

    @testset "TLSConfig Version Options" begin
        # TLSv1.2
        config_12 = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem",
            min_version = :TLSv1_2
        )
        @test config_12.min_version == :TLSv1_2

        # TLSv1.3
        config_13 = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem",
            min_version = :TLSv1_3
        )
        @test config_13.min_version == :TLSv1_3

        # Invalid version
        @test_throws ArgumentError TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem",
            min_version = :TLSv1_0
        )
    end

    @testset "Server Creation with TLS" begin
        config = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem"
        )

        server = GRPCServer("127.0.0.1", 50200; tls=config)

        @test server.config.tls !== nothing
        @test server.config.tls.cert_chain == "/path/to/cert.pem"
    end

    @testset "Server Show with TLS" begin
        config = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem"
        )

        server = GRPCServer("127.0.0.1", 50201; tls=config)
        str = sprint(show, server)

        @test occursin("TLS", str)
    end

    @testset "TLS Config Verification" begin
        # Test with non-existent files
        config = TLSConfig(
            cert_chain = "/nonexistent/cert.pem",
            private_key = "/nonexistent/key.pem"
        )

        @test !gRPCServer.verify_tls_config(config)
    end

    @testset "ALPN Protocol Setup" begin
        @test gRPCServer.ALPN_PROTOCOLS == ["h2"]
    end

    @testset "TLS Error Type" begin
        err = gRPCServer.TLSError("Test TLS error")
        @test err.message == "Test TLS error"

        str = sprint(showerror, err)
        @test occursin("TLSError", str)
        @test occursin("Test TLS error", str)
    end

    @testset "PeerInfo with Certificate" begin
        # Without certificate
        peer = PeerInfo(Sockets.IPv4("192.168.1.1"), 12345)
        @test peer.certificate === nothing

        # With certificate
        cert_data = UInt8[0x30, 0x82, 0x01, 0x00]  # Fake DER data
        peer_with_cert = PeerInfo(Sockets.IPv4("192.168.1.1"), 12345; certificate=cert_data)
        @test peer_with_cert.certificate == cert_data

        # Show method
        str = sprint(show, peer_with_cert)
        @test occursin("mTLS", str)
    end

    @testset "reload_tls! Validation" begin
        # Without TLS configured
        server_no_tls = GRPCServer("127.0.0.1", 50202)
        @test_throws ArgumentError reload_tls!(server_no_tls)

        # With TLS but not running
        config = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem"
        )
        server_with_tls = GRPCServer("127.0.0.1", 50203; tls=config)
        @test_throws InvalidServerStateError reload_tls!(server_with_tls)
    end

    @testset "TLS Certificate Reload Module" begin
        # Test the reload module exists and has expected functions
        @test isdefined(gRPCServer, :CertificateWatcher)

        # Create a watcher (requires valid TLSConfig)
        config = TLSConfig(
            cert_chain = "/path/to/cert.pem",
            private_key = "/path/to/key.pem"
        )
        callback = () -> nothing
        watcher = gRPCServer.CertificateWatcher(config, callback)

        @test watcher.config === config
        @test !watcher.watching
    end

    @testset "Server Without TLS" begin
        with_test_server() do ts
            @test ts.server.config.tls === nothing
            @test ts.server.status == ServerStatus.RUNNING

            # Can connect without TLS
            client = MockGRPCClient("127.0.0.1", ts.port)
            @test connect!(client)
            disconnect!(client)
        end
    end

    @testset "TLS in ServerConfig" begin
        config = ServerConfig(
            tls = TLSConfig(
                cert_chain = "/path/to/cert.pem",
                private_key = "/path/to/key.pem"
            )
        )

        @test config.tls !== nothing
        @test config.tls.cert_chain == "/path/to/cert.pem"

        # Show method
        str = sprint(show, config)
        @test occursin("tls=enabled", str)
    end

    @testset "ALPN Negotiation" begin
        # Test ALPN protocol verification
        # This would need an actual SSL context to test fully
        @test gRPCServer.ALPN_PROTOCOLS[1] == "h2"
    end

    @testset "TLS Context Creation Error Handling" begin
        # Test that invalid config throws TLSError
        config = TLSConfig(
            cert_chain = "/definitely/not/a/real/file.pem",
            private_key = "/also/not/real/key.pem"
        )

        @test_throws gRPCServer.TLSError gRPCServer.create_ssl_context(config)
    end

    # User Story 1: Basic TLS Server Setup Tests
    @testset "US1: TLS Server Accept Loop Integration" begin
        # Get the test certificate paths
        cert_dir = joinpath(@__DIR__, "..", "fixtures", "certs")
        server_cert = joinpath(cert_dir, "server.crt")
        server_key = joinpath(cert_dir, "server.key")
        ca_cert = joinpath(cert_dir, "ca.crt")

        # Skip if test certificates don't exist
        if !isfile(server_cert) || !isfile(server_key)
            @warn "Skipping TLS integration tests - test certificates not found" cert_dir
            return
        end

        @testset "TLS Server Starts Successfully" begin
            tls_config = TLSConfig(
                cert_chain = server_cert,
                private_key = server_key
            )

            port = rand(51100:51199)
            server = GRPCServer("127.0.0.1", port; tls=tls_config)

            try
                start!(server)
                @test server.status == ServerStatus.RUNNING
                @test server.ssl_context !== nothing
                sleep(0.1)  # Give server time to be fully ready
            finally
                stop!(server; force=true)
            end
        end

        @testset "TLS Server ssl_context Field Set" begin
            tls_config = TLSConfig(
                cert_chain = server_cert,
                private_key = server_key
            )

            port = rand(51200:51299)
            server = GRPCServer("127.0.0.1", port; tls=tls_config)

            # Before start, ssl_context should be nothing
            @test server.ssl_context === nothing

            try
                start!(server)
                # After start, ssl_context should be set
                @test server.ssl_context !== nothing
            finally
                stop!(server; force=true)
            end
        end

        @testset "TLS Server Show Method" begin
            tls_config = TLSConfig(
                cert_chain = server_cert,
                private_key = server_key
            )

            port = rand(51300:51399)
            server = GRPCServer("127.0.0.1", port; tls=tls_config)

            # Before start - TLS configured but not active
            str_before = sprint(show, server)
            @test occursin("TLS=configured", str_before)

            try
                start!(server)
                # After start - TLS active
                str_after = sprint(show, server)
                @test occursin("TLS=active", str_after)
            finally
                stop!(server; force=true)
            end
        end

        @testset "Plaintext Server Still Works (Backwards Compatibility)" begin
            # Server without TLS should work as before
            port = rand(51400:51499)
            server = GRPCServer("127.0.0.1", port)

            try
                start!(server)
                @test server.status == ServerStatus.RUNNING
                @test server.ssl_context === nothing
                @test server.config.tls === nothing

                # Plaintext connection should work
                client = MockGRPCClient("127.0.0.1", port)
                @test connect!(client)
                disconnect!(client)
            finally
                stop!(server; force=true)
            end
        end
    end
end
