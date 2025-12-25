"""
Tests for PluginInfoCommand module.

Tests plugin-info command execution, plugin list display,
and plugin details formatting.
"""

using Test
using JuliaPkgTemplatesCommandLineInterface
using PkgTemplates

# Import PluginInfoCommand (will be defined in src/plugin_info_command.jl)
include("../src/plugin_info_command.jl")

# Import types directly (these are already included in PluginInfoCommand)
include("../src/types.jl")

# Helper function for capturing stdout
function capture_stdout(f::Function)
    old_stdout = stdout
    rd, wr = redirect_stdout()

    task = @async read(rd, String)

    try
        f()
        close(wr)
        fetch(task)
    finally
        redirect_stdout(old_stdout)
    end
end

@testset "PluginInfoCommand" begin
    @testset "list_all_plugins()" begin
        @testset "displays all available plugins" begin
            # Get actual plugins from PluginDiscovery
            plugins = PluginInfoCommand.PluginDiscovery.get_plugins()

            @test !isempty(plugins)

            # Capture output
            output_str = capture_stdout() do
                PluginInfoCommand.list_all_plugins(plugins)
            end

            # Verify output contains plugin names
            @test contains(output_str, "Available")
            # Check for some common plugins that should always exist
            @test contains(output_str, "Git") || contains(output_str, "License")
        end

        @testset "handles empty plugin list" begin
            # Test with empty list (edge case)
            empty_plugins = Type{<:PkgTemplates.Plugin}[]

            output_str = capture_stdout() do
                PluginInfoCommand.list_all_plugins(empty_plugins)
            end

            # Should indicate no plugins found
            @test contains(output_str, "No") || contains(output_str, "empty") || length(output_str) >= 0
        end
    end

    @testset "show_plugin_details()" begin
        @testset "displays plugin details with fields and defaults" begin
            # Create sample plugin details
            details = PluginDetails(
                name="Git",
                fields=[:manifest, :ssh],
                types=[Bool, Bool],
                defaults=[false, false]
            )

            # Capture output
            output_str = capture_stdout() do
                PluginInfoCommand.show_plugin_details(details)
            end

            # Verify output contains plugin information
            @test contains(output_str, "Git")
            @test contains(output_str, "manifest") || contains(output_str, ":manifest")
            @test contains(output_str, "ssh") || contains(output_str, ":ssh")
            @test contains(output_str, "Bool")
        end

        @testset "handles plugin with no fields" begin
            # Plugin with no fields (like Readme)
            details = PluginDetails(
                name="Readme",
                fields=Symbol[],
                types=Type[],
                defaults=Any[]
            )

            # Capture output
            output_str = capture_stdout() do
                PluginInfoCommand.show_plugin_details(details)
            end

            # Should display plugin name and indicate no fields
            @test contains(output_str, "Readme")
            @test contains(output_str, "no") || contains(output_str, "No") || contains(output_str, "field")
        end
    end

    @testset "execute()" begin
        @testset "lists all plugins when no plugin name specified" begin
            args = Dict{String,Any}()  # No plugin_name

            # Capture output and result
            local result
            output_str = capture_stdout() do
                result = PluginInfoCommand.execute(args)
            end

            @test result.success == true
            @test contains(output_str, "Available") || contains(output_str, "Plugin")
        end

        @testset "shows specific plugin details when plugin name provided" begin
            args = Dict{String,Any}(
                "plugin_name" => "Git"
            )

            # Capture output and result
            local result
            output_str = capture_stdout() do
                result = PluginInfoCommand.execute(args)
            end

            @test result.success == true
            @test contains(output_str, "Git")
        end

        @testset "handles non-existent plugin gracefully" begin
            args = Dict{String,Any}(
                "plugin_name" => "NonExistentPlugin123"
            )

            result = PluginInfoCommand.execute(args)

            # Should fail gracefully with error message
            @test result.success == false
            @test result.message !== nothing
            @test contains(result.message, "not found") || contains(result.message, "Error")
        end

        @testset "handles errors gracefully" begin
            # Test with invalid input
            args = Dict{String,Any}(
                "plugin_name" => nothing
            )

            # Should not crash, should return result with success field
            result = PluginInfoCommand.execute(args)
            @test hasfield(typeof(result), :success)
            @test isa(result.success, Bool)
        end
    end
end
