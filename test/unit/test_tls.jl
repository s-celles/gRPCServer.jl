# Unit tests for TLS configuration

using Test
using gRPCServer

# Helper to get test certificate paths
function get_test_cert_paths()
    certs_dir = joinpath(@__DIR__, "..", "fixtures", "certs")
    return (
        ca_cert = joinpath(certs_dir, "ca.crt"),
        ca_key = joinpath(certs_dir, "ca.key"),
        server_cert = joinpath(certs_dir, "server.crt"),
        server_key = joinpath(certs_dir, "server.key"),
        certs_dir = certs_dir
    )
end

# Check if test certificates are available
function test_certs_available()
    paths = get_test_cert_paths()
    return isfile(paths.server_cert) && isfile(paths.server_key)
end

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

    @testset "ALPN Functions" begin
        # Test get_negotiated_protocol - always returns "h2"
        @test gRPCServer.get_negotiated_protocol(nothing) == "h2"

        # Test verify_http2_negotiated - always returns true
        @test gRPCServer.verify_http2_negotiated(nothing) == true
    end

    @testset "TLSError Exception" begin
        err = gRPCServer.TLSError("Test error message")
        @test err isa Exception
        @test err.message == "Test error message"

        # Test showerror
        io = IOBuffer()
        showerror(io, err)
        @test String(take!(io)) == "TLSError: Test error message"
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

    @testset "verify_tls_config with missing key file" begin
        # Create a temp file for cert only
        mktempdir() do dir
            cert_path = joinpath(dir, "server.crt")
            write(cert_path, "dummy cert")

            config = TLSConfig(
                cert_chain = cert_path,
                private_key = "/nonexistent/server.key"
            )
            @test gRPCServer.verify_tls_config(config) == false
        end
    end

    @testset "verify_tls_config with missing client CA" begin
        # Create temp files for cert and key
        mktempdir() do dir
            cert_path = joinpath(dir, "server.crt")
            key_path = joinpath(dir, "server.key")
            write(cert_path, "dummy cert")
            write(key_path, "dummy key")

            config = TLSConfig(
                cert_chain = cert_path,
                private_key = key_path,
                client_ca = "/nonexistent/ca.crt"
            )
            @test gRPCServer.verify_tls_config(config) == false
        end
    end

    @testset "Server with TLS Configuration" begin
        config = TLSConfig(
            cert_chain = "/path/to/server.crt",
            private_key = "/path/to/server.key"
        )

        server = GRPCServer("0.0.0.0", 50051; tls = config)
        @test server.config.tls === config
    end

    # Tests with real certificates (if available)
    if test_certs_available()
        paths = get_test_cert_paths()

        @testset "verify_tls_config with real certificates" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key
            )
            @test gRPCServer.verify_tls_config(config) == true
        end

        @testset "verify_tls_config with real certificates and CA" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key,
                client_ca = paths.ca_cert
            )
            @test gRPCServer.verify_tls_config(config) == true
        end

        @testset "create_ssl_context with real certificates" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key
            )

            ctx = gRPCServer.create_ssl_context(config)
            @test ctx !== nothing
        end

        @testset "create_ssl_context with TLS 1.3" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key,
                min_version = :TLSv1_3
            )

            ctx = gRPCServer.create_ssl_context(config)
            @test ctx !== nothing
        end

        @testset "create_ssl_context with mTLS config" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key,
                client_ca = paths.ca_cert,
                require_client_cert = true
            )

            # Should warn about mTLS but still create context
            ctx = gRPCServer.create_ssl_context(config)
            @test ctx !== nothing
        end

        @testset "create_ssl_context with invalid cert fails" begin
            mktempdir() do dir
                invalid_cert = joinpath(dir, "invalid.crt")
                invalid_key = joinpath(dir, "invalid.key")
                write(invalid_cert, "not a valid certificate")
                write(invalid_key, "not a valid key")

                config = TLSConfig(
                    cert_chain = invalid_cert,
                    private_key = invalid_key
                )

                @test_throws gRPCServer.TLSError gRPCServer.create_ssl_context(config)
            end
        end

        @testset "CertificateWatcher with real certificates" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key
            )

            reload_count = Ref(0)
            watcher = gRPCServer.CertificateWatcher(config, () -> reload_count[] += 1)

            # Start watching with short interval
            gRPCServer.start_watching!(watcher; interval=0.1)
            @test watcher.watching == true
            @test haskey(watcher.last_modified, paths.server_cert)
            @test haskey(watcher.last_modified, paths.server_key)

            # Check modification times were recorded
            @test watcher.last_modified[paths.server_cert] > 0
            @test watcher.last_modified[paths.server_key] > 0

            # Stop watching
            gRPCServer.stop_watching!(watcher)
            @test watcher.watching == false
            sleep(0.2)  # Let async task exit
        end

        @testset "CertificateWatcher with CA certificate" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key,
                client_ca = paths.ca_cert
            )

            watcher = gRPCServer.CertificateWatcher(config, () -> nothing)
            gRPCServer.start_watching!(watcher; interval=1.0)

            @test haskey(watcher.last_modified, paths.ca_cert)

            gRPCServer.stop_watching!(watcher)
        end

        @testset "CertificateWatcher check_for_changes!" begin
            # Use temp copies to test file modification detection
            mktempdir() do dir
                # Copy certificates to temp directory
                temp_cert = joinpath(dir, "server.crt")
                temp_key = joinpath(dir, "server.key")
                cp(paths.server_cert, temp_cert)
                cp(paths.server_key, temp_key)

                config = TLSConfig(
                    cert_chain = temp_cert,
                    private_key = temp_key
                )

                reload_count = Ref(0)
                watcher = gRPCServer.CertificateWatcher(config, () -> reload_count[] += 1)

                # Manually set up last_modified (simulating start_watching!)
                watcher.last_modified[temp_cert] = mtime(temp_cert)
                watcher.last_modified[temp_key] = mtime(temp_key)

                # First check - no changes
                gRPCServer.check_for_changes!(watcher)
                @test reload_count[] == 0

                # Modify certificate file
                sleep(0.1)  # Ensure mtime changes
                touch(temp_cert)

                # Second check - should detect change
                gRPCServer.check_for_changes!(watcher)
                @test reload_count[] == 1

                # Third check - no new changes
                gRPCServer.check_for_changes!(watcher)
                @test reload_count[] == 1
            end
        end

        @testset "setup_alpn! with real SSL context" begin
            config = TLSConfig(
                cert_chain = paths.server_cert,
                private_key = paths.server_key
            )

            # Create context first
            ctx = gRPCServer.create_ssl_context(config)

            # setup_alpn! should not throw
            gRPCServer.setup_alpn!(ctx)
            gRPCServer.setup_alpn!(ctx, ["h2", "http/1.1"])

            @test true  # If we get here, no errors
        end

        @testset "get_peer_certificate with nothing" begin
            # Test with nothing - should return nothing
            result = gRPCServer.get_peer_certificate(nothing)
            @test result === nothing
        end

        @testset "close_tls_socket with nothing" begin
            # Test with nothing - should not throw
            gRPCServer.close_tls_socket(nothing)
            @test true  # If we get here, no errors
        end
    else
        @warn "Test certificates not available. Run `julia test/fixtures/generate_test_certs.jl` to generate them."
    end
end
