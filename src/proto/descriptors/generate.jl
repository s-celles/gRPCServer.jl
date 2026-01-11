#!/usr/bin/env julia
#
# Generate protobuf descriptor files (.pb) from .proto sources
#
# Usage:
#   julia src/proto/descriptors/generate.jl
#
# Prerequisites:
#   - protoc (Protocol Buffer Compiler) must be installed and in PATH
#     - Linux: apt-get install protobuf-compiler
#     - macOS: brew install protobuf
#     - Windows: choco install protoc OR download from https://github.com/protocolbuffers/protobuf/releases
#

"""
Find protoc executable in PATH, checking common locations on different platforms.
Returns the path to protoc or nothing if not found.
"""
function find_protoc()
    # Try standard PATH first
    protoc_cmd = Sys.iswindows() ? "protoc.exe" : "protoc"

    # Check if protoc is in PATH
    try
        protoc_path = Sys.which(protoc_cmd)
        if protoc_path !== nothing
            return protoc_path
        end
    catch
        # Sys.which may throw on some platforms
    end

    # Check common installation locations
    common_paths = if Sys.iswindows()
        [
            joinpath(ENV["ProgramFiles"], "protoc", "bin", "protoc.exe"),
            joinpath(get(ENV, "LOCALAPPDATA", ""), "protoc", "bin", "protoc.exe"),
            joinpath(get(ENV, "USERPROFILE", ""), "scoop", "shims", "protoc.exe"),
        ]
    elseif Sys.isapple()
        [
            "/opt/homebrew/bin/protoc",  # Apple Silicon Homebrew
            "/usr/local/bin/protoc",      # Intel Homebrew
            "/opt/local/bin/protoc",      # MacPorts
        ]
    else  # Linux and other Unix-like
        [
            "/usr/bin/protoc",
            "/usr/local/bin/protoc",
            joinpath(get(ENV, "HOME", ""), ".local", "bin", "protoc"),
        ]
    end

    for path in common_paths
        if isfile(path)
            return path
        end
    end

    return nothing
end

"""
Check protoc version and return it as a string.
"""
function protoc_version(protoc_path::String)
    try
        output = read(`$protoc_path --version`, String)
        return strip(output)
    catch e
        return "unknown (error: $e)"
    end
end

"""
Generate a .pb descriptor file from a .proto file.
"""
function generate_descriptor(protoc_path::String, proto_file::String, output_file::String, proto_path::String)
    # Ensure output directory exists
    mkpath(dirname(output_file))

    # Build protoc command
    cmd = `$protoc_path --descriptor_set_out=$output_file --include_imports --proto_path=$proto_path $proto_file`

    println("  Generating: $(basename(output_file))")
    println("    From: $proto_file")
    println("    Command: $cmd")

    try
        run(cmd)

        # Verify output was created
        if isfile(output_file)
            size = filesize(output_file)
            println("    Success: $(output_file) ($(size) bytes)")
            return true
        else
            println("    Error: Output file was not created")
            return false
        end
    catch e
        println("    Error: $e")
        return false
    end
end

function main()
    println("=" ^ 60)
    println("gRPCServer.jl - Proto Descriptor Generator")
    println("=" ^ 60)
    println()

    # Find project root (where Project.toml is)
    script_dir = @__DIR__
    project_root = dirname(dirname(dirname(script_dir)))

    # Verify we're in the right place
    if !isfile(joinpath(project_root, "Project.toml"))
        # Try alternative: script might be run from project root
        project_root = pwd()
        if !isfile(joinpath(project_root, "Project.toml"))
            error("Could not find Project.toml. Please run from the gRPCServer project directory.")
        end
    end

    println("Project root: $project_root")
    println()

    # Find protoc
    println("Looking for protoc...")
    protoc_path = find_protoc()

    if protoc_path === nothing
        println()
        println("ERROR: protoc not found!")
        println()
        println("Please install Protocol Buffer Compiler:")
        println("  - Linux:   apt-get install protobuf-compiler")
        println("  - macOS:   brew install protobuf")
        println("  - Windows: choco install protoc")
        println("             OR download from https://github.com/protocolbuffers/protobuf/releases")
        exit(1)
    end

    println("  Found: $protoc_path")
    println("  Version: $(protoc_version(protoc_path))")
    println()

    # Define proto files and their outputs
    contracts_dir = joinpath(project_root, "specs", "001-grpc-server", "contracts")
    output_dir = joinpath(project_root, "src", "proto", "descriptors")

    descriptors = [
        (
            proto = joinpath(contracts_dir, "health.proto"),
            output = joinpath(output_dir, "health.pb"),
            name = "Health Service"
        ),
        (
            proto = joinpath(contracts_dir, "reflection.proto"),
            output = joinpath(output_dir, "reflection.pb"),
            name = "Reflection Service"
        ),
    ]

    # Verify proto files exist
    println("Checking proto files...")
    for desc in descriptors
        if !isfile(desc.proto)
            error("Proto file not found: $(desc.proto)")
        end
        println("  Found: $(desc.proto)")
    end
    println()

    # Generate descriptors
    println("Generating descriptors...")
    println()

    success_count = 0
    for desc in descriptors
        println("$(desc.name):")
        if generate_descriptor(protoc_path, desc.proto, desc.output, contracts_dir)
            success_count += 1
        end
        println()
    end

    # Summary
    println("=" ^ 60)
    println("Summary: $success_count/$(length(descriptors)) descriptors generated successfully")
    println("=" ^ 60)

    if success_count != length(descriptors)
        exit(1)
    end

    println()
    println("Next steps:")
    println("  1. The .pb files are now in: $output_dir")
    println("  2. These will be loaded by src/proto/descriptors.jl")
    println("  3. Run tests: julia --project -e 'using Pkg; Pkg.test()'")
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
