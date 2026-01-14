#!/usr/bin/env julia
using Pkg
Pkg.activate(".")

using gRPCServer

# Create server with reflection enabled
host = "127.0.0.1"
port = 50051
server = GRPCServer(host, port; enable_reflection=true, enable_health_check=true)

# Start server
start!(server)

println("Server started on port $port")
println("Server status: ", server.status)
println("Services: ", services(server))

# Keep server running
while true
    sleep(1.0)
end
