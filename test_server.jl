#!/usr/bin/env julia
using Pkg
Pkg.activate(".")

using gRPCServer

# Create server with reflection enabled
server = GRPCServer("0.0.0.0", 50051; enable_reflection=true, enable_health_check=true)

# Start server
start!(server)

println("Server started on port 50051")
println("Server status: ", server.status)
println("Services: ", services(server))

# Keep server running
while true
    sleep(1.0)
end
