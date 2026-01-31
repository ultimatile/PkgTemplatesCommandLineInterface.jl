"""
Tests for CompletionCommand module.

Tests completion command execution and shell completion script generation.
"""

using Test
using JuliaPkgTemplatesCommandLineInterface

# Access CompletionCommand through parent module
const CompletionCommand = JuliaPkgTemplatesCommandLineInterface.CompletionCommand

# Helper function for capturing stdout (same as test_integration.jl)
function capture_stdout(f::Function)
    old_stdout = stdout
    (read_pipe, write_pipe) = redirect_stdout()

    f()

    redirect_stdout(old_stdout)
    close(write_pipe)
    output = String(read(read_pipe))
    close(read_pipe)

    return output
end

@testset "CompletionCommand" begin
    @testset "execute()" begin
        @testset "generates fish completion script by default" begin
            args = Dict{String,Any}()  # No shell specified, defaults to fish

            # Capture output and result
            local result
            output_str = capture_stdout() do
                result = CompletionCommand.execute(args)
            end

            @test result.success == true
            # Fish completion script should contain complete commands
            @test contains(output_str, "complete -c jtc")
            @test contains(output_str, "create")
            @test contains(output_str, "config")
            @test contains(output_str, "plugin-info")
            @test contains(output_str, "completion")
        end

        @testset "generates fish completion script when specified" begin
            args = Dict{String,Any}(
                "shell" => "fish"
            )

            # Capture output and result
            local result
            output_str = capture_stdout() do
                result = CompletionCommand.execute(args)
            end

            @test result.success == true
            @test contains(output_str, "complete -c jtc")
            # Should include dynamic plugin names
            @test contains(output_str, "Git") || contains(output_str, "License")
        end

        @testset "handles unsupported shell gracefully" begin
            args = Dict{String,Any}(
                "shell" => "powershell"  # Unsupported
            )

            result = CompletionCommand.execute(args)

            # Should fail gracefully with error message
            @test result.success == false
            @test result.message !== nothing
            @test contains(result.message, "Unsupported") || contains(result.message, "supported")
        end

        @testset "includes plugin names in completion output" begin
            args = Dict{String,Any}(
                "shell" => "fish"
            )

            # Capture output
            local result
            output_str = capture_stdout() do
                result = CompletionCommand.execute(args)
            end

            @test result.success == true
            # Get actual plugins and verify at least one is in output
            plugins = JuliaPkgTemplatesCommandLineInterface.PluginDiscovery.get_plugins()
            @test !isempty(plugins)

            # Check if at least some plugin names appear in completion
            plugin_names = String[String(nameof(p)) for p in plugins]
            found_plugin = any(pname -> contains(output_str, pname), plugin_names)
            @test found_plugin
        end

        @testset "handles template generation errors gracefully" begin
            # This test verifies error handling
            # The actual template error would require mocking or file manipulation
            # For now, we just verify the command doesn't crash
            args = Dict{String,Any}(
                "shell" => "fish"
            )

            result = CompletionCommand.execute(args)
            @test hasfield(typeof(result), :success)
            @test isa(result.success, Bool)
        end
    end
end
