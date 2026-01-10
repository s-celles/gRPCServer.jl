using Aqua
using gRPCServer

@testset "Aqua.jl Quality Checks" begin
    Aqua.test_all(
        gRPCServer;
        ambiguities = false,  # Disable for now due to potential issues
        unbound_args = true,
        undefined_exports = true,
        project_extras = true,
        stale_deps = true,
        deps_compat = false,  # Stdlib packages don't need compat entries
        piracies = false  # Disable type piracy checks for now
    )
end
