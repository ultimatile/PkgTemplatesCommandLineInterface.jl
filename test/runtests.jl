using JuliaPkgTemplatesCommandLineInterface
using Test
using Aqua

@testset "JuliaPkgTemplatesCommandLineInterface.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        # Skip stale_deps and project_extras checks during initial development
        # Will be re-enabled after core implementation is complete
        Aqua.test_all(
            JuliaPkgTemplatesCommandLineInterface;
            stale_deps=false,
            deps_compat=(check_extras=false,)
        )
    end
    # Write your tests here.
end
