# Script to generate test certificates for TLS testing
# Run with: julia test/fixtures/generate_test_certs.jl
#
# Prerequisites: openssl command-line tool must be installed

const CERTS_DIR = joinpath(@__DIR__, "certs")

"""
    generate_test_certificates(; force::Bool=false)

Generate self-signed certificates for TLS testing using openssl CLI.
Creates:
- ca.crt / ca.key - Certificate Authority
- server.crt / server.key - Server certificate

Set `force=true` to regenerate existing certificates.
"""
function generate_test_certificates(; force::Bool=false)
    # Check if openssl is available
    try
        run(pipeline(`openssl version`, stdout=devnull, stderr=devnull))
    catch
        error("openssl command not found. Please install OpenSSL.")
    end

    # Create certs directory if it doesn't exist
    mkpath(CERTS_DIR)

    ca_key = joinpath(CERTS_DIR, "ca.key")
    ca_cert = joinpath(CERTS_DIR, "ca.crt")
    server_key = joinpath(CERTS_DIR, "server.key")
    server_cert = joinpath(CERTS_DIR, "server.crt")

    # Check if certificates already exist
    if !force && isfile(ca_cert) && isfile(server_cert)
        println("Test certificates already exist in: $CERTS_DIR")
        println("Use generate_test_certificates(force=true) to regenerate.")
        return (ca_cert=ca_cert, ca_key=ca_key, server_cert=server_cert, server_key=server_key)
    end

    println("Generating test certificates in: $CERTS_DIR")

    # Generate CA private key and self-signed certificate
    println("  Generating CA certificate...")
    run(```
        openssl req -x509 -newkey rsa:2048
        -keyout $ca_key
        -out $ca_cert
        -days 365 -nodes
        -subj "/CN=TestCA/O=gRPCServer.jl Test/C=US"
    ```)

    # Generate server private key and self-signed certificate
    println("  Generating server certificate...")
    run(```
        openssl req -x509 -newkey rsa:2048
        -keyout $server_key
        -out $server_cert
        -days 365 -nodes
        -subj "/CN=localhost/O=gRPCServer.jl Test/C=US"
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    ```)

    println("\nTest certificates generated successfully!")
    println("Files created:")
    for f in readdir(CERTS_DIR)
        path = joinpath(CERTS_DIR, f)
        size = filesize(path)
        println("  - $f ($size bytes)")
    end

    return (ca_cert=ca_cert, ca_key=ca_key, server_cert=server_cert, server_key=server_key)
end

"""
    cleanup_test_certificates()

Remove generated test certificates.
"""
function cleanup_test_certificates()
    if isdir(CERTS_DIR)
        rm(CERTS_DIR; recursive=true)
        println("Removed test certificates directory: $CERTS_DIR")
    else
        println("No certificates directory found.")
    end
end

"""
    get_test_cert_paths() -> NamedTuple

Get paths to test certificates. Returns nothing for missing files.
"""
function get_test_cert_paths()
    ca_cert = joinpath(CERTS_DIR, "ca.crt")
    ca_key = joinpath(CERTS_DIR, "ca.key")
    server_cert = joinpath(CERTS_DIR, "server.crt")
    server_key = joinpath(CERTS_DIR, "server.key")

    return (
        ca_cert = isfile(ca_cert) ? ca_cert : nothing,
        ca_key = isfile(ca_key) ? ca_key : nothing,
        server_cert = isfile(server_cert) ? server_cert : nothing,
        server_key = isfile(server_key) ? server_key : nothing,
        available = isfile(server_cert) && isfile(server_key)
    )
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    generate_test_certificates()
end
