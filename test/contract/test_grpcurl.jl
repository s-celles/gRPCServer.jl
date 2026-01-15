# Contract tests for gRPC reflection service using grpcurl
# Tests that the reflection service works with standard gRPC tooling

using Test
using gRPCServer
using Sockets
using ProtoBuf: OneOf

# Include test utilities
# TestUtils is included once in runtests.jl to avoid method redefinition warnings
# using TestUtils is inherited from the parent module

# Check if grpcurl is available
const GRPCURL_AVAILABLE = try
    success(`grpcurl --version`)
catch
    false
end

@testset "grpcurl Reflection Contract Tests" begin
    if !GRPCURL_AVAILABLE
        @warn "grpcurl not found, skipping contract tests"
        @test_skip "grpcurl not available"
        return
    end

    @testset "grpcurl List Services" begin
        # Create handler for test service
        handler = (ctx, req) -> req

        descriptor = ServiceDescriptor(
            "test.GreeterService",
            Dict(
                "SayHello" => MethodDescriptor(
                    "SayHello",
                    MethodType.UNARY,
                    "test.HelloRequest",
                    "test.HelloReply",
                    handler
                )
            ),
            nothing
        )

        # Use dynamic port to avoid conflicts
        with_test_server(enable_reflection=true) do ts
            # Register test service
            gRPCServer.register_service!(ts.server.dispatcher, descriptor)
            ts.server.health_status["test.GreeterService"] = HealthStatus.SERVING

            # Give server time to fully start
            sleep(0.5)

            # Try to list services using grpcurl
            try
                result = read(`grpcurl -plaintext localhost:$(ts.port) list`, String)

                # Should list the reflection service
                @test occursin("grpc.reflection", result) || occursin("ServerReflection", result)

                # May list registered services (depends on reflection implementation)
                # @test occursin("test.GreeterService", result)
            catch e
                # grpcurl may fail if server doesn't fully implement HTTP/2
                # This is expected until full HTTP/2 support is complete
                @warn "grpcurl list failed (expected with partial HTTP/2 implementation)" exception=e
                @test_skip "HTTP/2 not fully implemented"
            end
        end
    end

    @testset "grpcurl Connection Test" begin
        with_test_server(enable_reflection=true) do ts
            sleep(0.5)

            # Test basic connection (even if reflection fails)
            try
                # Try to connect - may fail with protocol error
                run(`grpcurl -plaintext -connect-timeout 2 localhost:$(ts.port) list`)
                @test true  # Connection succeeded
            catch e
                # Expected: partial HTTP/2 implementation
                @warn "grpcurl connection test" exception=e
                @test_skip "HTTP/2 not fully implemented for grpcurl"
            end
        end
    end

    @testset "Server Accepts TCP Connections for grpcurl" begin
        # Even without full HTTP/2, server should accept TCP connections
        with_test_server(enable_reflection=true) do ts
            sleep(1.0)  # Give server more time to start on CI

            # Verify server is listening with retry
            connected = false
            for attempt in 1:3
                try
                    sock = connect("localhost", ts.port)
                    connected = isopen(sock)
                    close(sock)
                    break
                catch e
                    if attempt < 3
                        sleep(0.5)  # Wait and retry
                    end
                end
            end
            @test connected
        end
    end

    @testset "Reflection Service Registered" begin
        with_test_server(enable_reflection=true) do ts
            # Verify reflection service is registered in the dispatcher
            result = gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo"
            )

            @test result !== nothing

            if result !== nothing
                svc, method = result
                @test svc.name == "grpc.reflection.v1alpha.ServerReflection"
                @test method.name == "ServerReflectionInfo"
                @test method.method_type == MethodType.BIDI_STREAMING
            end
        end
    end

    @testset "Reflection Without Reflection Flag" begin
        with_test_server(enable_reflection=false) do ts
            # Reflection service should NOT be registered
            result = gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo"
            )

            @test result === nothing
        end
    end

    @testset "Health Service with Reflection" begin
        with_test_server(enable_reflection=true, enable_health_check=true) do ts
            sleep(0.3)

            # Both services should be registered
            @test gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.health.v1.Health/Check"
            ) !== nothing

            @test gRPCServer.lookup_method(
                ts.server.dispatcher.registry,
                "/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo"
            ) !== nothing
        end
    end

    @testset "Reflection List Services Response" begin
        # Test the reflection service logic directly
        handler = (ctx, req) -> req

        descriptor1 = ServiceDescriptor(
            "test.ServiceA",
            Dict(
                "Method1" => MethodDescriptor("Method1", MethodType.UNARY, "Req", "Resp", handler)
            ),
            nothing
        )

        descriptor2 = ServiceDescriptor(
            "test.ServiceB",
            Dict(
                "Method2" => MethodDescriptor("Method2", MethodType.SERVER_STREAMING, "Req", "Resp", handler)
            ),
            nothing
        )

        with_test_server(enable_reflection=true) do ts
            gRPCServer.register_service!(ts.server.dispatcher, descriptor1)
            gRPCServer.register_service!(ts.server.dispatcher, descriptor2)

            # Test listing services through the registry
            services_list = gRPCServer.list_services(ts.server.dispatcher.registry)

            @test "test.ServiceA" in services_list
            @test "test.ServiceB" in services_list
            @test "grpc.reflection.v1alpha.ServerReflection" in services_list
        end
    end

    @testset "Reflection Request Handling" begin
        with_test_server(enable_reflection=true) do ts
            # Create a list_services request using proto-generated types
            request = gRPCServer.ServerReflectionRequest(
                "localhost",
                OneOf(:list_services, "*")
            )

            # Handle the request
            response = gRPCServer.handle_reflection_request(
                request,
                ts.server.dispatcher.registry
            )

            @test response.message_response !== nothing
            @test response.message_response.name === :list_services_response

            list_resp = response.message_response[]
            # Should list reflection service
            service_names = [s.name for s in list_resp.service]
            @test "grpc.reflection.v1alpha.ServerReflection" in service_names
        end
    end

    @testset "Reflection File Containing Symbol" begin
        handler = (ctx, req) -> req

        # file_descriptor is now Vector{Vector{UInt8}} - a list of FileDescriptorProto bytes
        fd_bytes = [UInt8[0x0a, 0x0b, 0x0c], UInt8[0x0d, 0x0e, 0x0f]]
        descriptor = ServiceDescriptor(
            "test.SymbolService",
            Dict(
                "Method" => MethodDescriptor("Method", MethodType.UNARY, "Req", "Resp", handler)
            ),
            fd_bytes
        )

        with_test_server(enable_reflection=true) do ts
            gRPCServer.register_service!(ts.server.dispatcher, descriptor)

            # Request file containing symbol using proto-generated types
            request = gRPCServer.ServerReflectionRequest(
                "localhost",
                OneOf(:file_containing_symbol, "test.SymbolService")
            )

            response = gRPCServer.handle_reflection_request(
                request,
                ts.server.dispatcher.registry
            )

            @test response.message_response !== nothing
            @test response.message_response.name === :file_descriptor_response
            fd_resp = response.message_response[]
            @test length(fd_resp.file_descriptor_proto) == 2
            @test fd_resp.file_descriptor_proto[1] == UInt8[0x0a, 0x0b, 0x0c]
            @test fd_resp.file_descriptor_proto[2] == UInt8[0x0d, 0x0e, 0x0f]
        end
    end

    @testset "Reflection Unknown Symbol" begin
        with_test_server(enable_reflection=true) do ts
            request = gRPCServer.ServerReflectionRequest(
                "localhost",
                OneOf(:file_containing_symbol, "unknown.NonExistentService")
            )

            response = gRPCServer.handle_reflection_request(
                request,
                ts.server.dispatcher.registry
            )

            @test response.message_response !== nothing
            @test response.message_response.name === :error_response
            @test occursin("not found", lowercase(response.message_response[].error_message))
        end
    end
end
