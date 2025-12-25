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

    # Include test files
    include("test_project_setup.jl")
    include("test_errors.jl")
    include("test_types.jl")
    include("test_config_manager.jl")
    include("test_plugin_discovery.jl")
    include("test_template_manager.jl")
    include("test_package_generator.jl")
    include("test_create_command.jl")
    include("test_config_command.jl")
    include("test_plugin_info_command.jl")
end
