"""
Integration Tests for Component Integration (Task 7.1)

Tests the complete flow:
- CLI Layer → Commands Layer → Core Layer
- Error handling integration across all layers
- Dry-run mode verification across components
"""

using Test
using JuliaPkgTemplatesCommandLineInterface
using ArgParse
using TOML

@testset "Component Integration Tests (Task 7.1)" begin
    @testset "CLI → Commands → Core Flow Integration" begin
        @testset "Full create command flow with config merge" begin
            mktempdir() do tmpdir
                # Setup: Create a test config file
                config_dir = joinpath(tmpdir, ".config", "jtc")
                mkpath(config_dir)
                config_path = joinpath(config_dir, "config.toml")

                # Write test config with default author
                test_config = Dict(
                    "default" => Dict(
                        "author" => "Config Author",
                        "user" => "config_user",
                        "with_mise" => false
                    )
                )
                open(config_path, "w") do io
                    TOML.print(io, test_config)
                end

                # Test: CLI args should override config values
                # Set XDG_CONFIG_HOME to use our test config
                withenv("XDG_CONFIG_HOME" => joinpath(tmpdir, ".config")) do
                    # Parse arguments as if from command line
                    settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()
                    JuliaPkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)

                    # Simulate: jtc create TestPkg --author "CLI Author" --output-dir tmpdir
                    args = ["create", "TestPkg", "--author", "CLI Author", "--output-dir", tmpdir]
                    parsed_args = ArgParse.parse_args(args, settings)

                    # Execute create command (full integration)
                    result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                        "create",
                        parsed_args["create"]
                    )

                    # Verify: Command should succeed
                    @test result.success == true

                    # Verify: Package should be created
                    pkg_dir = joinpath(tmpdir, "TestPkg")
                    @test isdir(pkg_dir)

                    # Verify: Project.toml should exist and contain CLI author (not config author)
                    project_toml = joinpath(pkg_dir, "Project.toml")
                    @test isfile(project_toml)

                    project_data = TOML.parsefile(project_toml)
                    # CLI argument should override config file
                    @test occursin("CLI Author", join(project_data["authors"], ", "))
                end
            end
        end

        @testset "Config command flow: set → show round-trip" begin
            mktempdir() do tmpdir
                withenv("XDG_CONFIG_HOME" => tmpdir) do
                    # Test: Set config value
                    set_args = Dict{String, Any}(
                        "%SUBCOMMAND%" => "set",
                        "author" => "Integration Test Author"
                    )

                    set_result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                        "config",
                        set_args
                    )

                    @test set_result.success == true

                    # Test: Show config value (verify persistence)
                    show_args = Dict{String, Any}(
                        "%SUBCOMMAND%" => "show"
                    )

                    # Capture stdout for config show
                    old_stdout = stdout
                    (read_pipe, write_pipe) = redirect_stdout()

                    show_result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                        "config",
                        show_args
                    )
                    @test show_result.success == true

                    redirect_stdout(old_stdout)
                    close(write_pipe)
                    output = String(read(read_pipe))
                    close(read_pipe)

                    @test occursin("Integration Test Author", output)
                end
            end
        end

        @testset "Plugin-info command flow with PluginDiscovery" begin
            # Test: List all plugins (integration with PkgTemplates.jl)
            args = Dict{String, Any}()

            old_stdout = stdout
            (read_pipe, write_pipe) = redirect_stdout()

            result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                "plugin-info",
                args
            )
            @test result.success == true

            redirect_stdout(old_stdout)
            close(write_pipe)
            output = String(read(read_pipe))
            close(read_pipe)

            # Should list standard PkgTemplates plugins
            @test occursin("Git", output)
        end

        @testset "Completion command flow with TemplateManager" begin
            # Test: Generate fish completion script
            args = Dict{String, Any}("shell" => "fish")

            old_stdout = stdout
            (read_pipe, write_pipe) = redirect_stdout()

            result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                "completion",
                args
            )
            @test result.success == true

            redirect_stdout(old_stdout)
            close(write_pipe)
            output = String(read(read_pipe))
            close(read_pipe)

            # Verify completion script contains expected content
            @test occursin("complete -c jtc", output)
            @test occursin("create", output)
        end
    end

    @testset "Error Handling Flow Integration" begin
        @testset "PkgTemplates.jl error → PackageGenerationError conversion" begin
            mktempdir() do tmpdir
                # Test: Invalid package name should trigger PkgTemplates error
                args = Dict{String, Any}(
                    "package_name" => "invalid-package-name",  # Invalid: contains hyphen
                    "output-dir" => tmpdir
                )

                result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                    "create",
                    args
                )

                # Should return error result (not throw exception)
                @test result.success == false
                @test result.message !== nothing
                # Error message should be user-friendly
                @test occursin("error", lowercase(result.message)) ||
                      occursin("invalid", lowercase(result.message))
            end
        end

        @testset "TOML parse error → ConfigurationError conversion" begin
            mktempdir() do tmpdir
                # Setup: Create invalid TOML file
                config_dir = joinpath(tmpdir, ".config", "jtc")
                mkpath(config_dir)
                config_path = joinpath(config_dir, "config.toml")

                # Write invalid TOML
                write(config_path, "invalid toml syntax {{{ ")

                withenv("XDG_CONFIG_HOME" => joinpath(tmpdir, ".config")) do
                    # Test: Should fall back to default config (not crash)
                    args = Dict{String, Any}(
                        "%SUBCOMMAND%" => "show"
                    )

                    old_stdout = stdout
                    (read_pipe, write_pipe) = redirect_stdout()

                    result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                        "config",
                        args
                    )
                    # Should succeed with default config
                    @test result.success == true

                    redirect_stdout(old_stdout)
                    close(write_pipe)
                    output = String(read(read_pipe))
                    close(read_pipe)

                    # Should show default config (not corrupted config)
                    @test occursin("default", output)
                end
            end
        end

        @testset "Global error handler catches unhandled exceptions" begin
            # Test: Unknown command should be caught by handle_error
            unknown_error = ErrorException("Test unexpected error")
            result = JuliaPkgTemplatesCommandLineInterface.handle_error(unknown_error)

            @test result.success == false
            @test occursin("Unexpected error", result.message)
            @test occursin("Test unexpected error", result.message)
        end
    end

    @testset "Dry-Run Mode Integration" begin
        @testset "Dry-run mode prevents package creation" begin
            mktempdir() do tmpdir
                # Test: Create package with --dry-run
                args = Dict{String, Any}(
                    "package_name" => "DryRunTest",
                    "output-dir" => tmpdir,
                    "dry-run" => true
                )

                result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                    "create",
                    args
                )

                # Should succeed
                @test result.success == true

                # But should NOT create the package directory
                pkg_dir = joinpath(tmpdir, "DryRunTest")
                @test !isdir(pkg_dir)
            end
        end

        @testset "Dry-run mode shows execution plan" begin
            mktempdir() do tmpdir
                # Test: Dry-run should output what would be done
                args = Dict{String, Any}(
                    "package_name" => "DryRunTest",
                    "output-dir" => tmpdir,
                    "dry-run" => true,
                    "author" => "Test Author"
                )

                # Capture output
                old_stdout = stdout
                (read_pipe, write_pipe) = redirect_stdout()

                result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(
                    "create",
                    args
                )
                @test result.success == true

                redirect_stdout(old_stdout)
                close(write_pipe)
                output = String(read(read_pipe))
                close(read_pipe)

                # Should show what would be created
                @test occursin("DryRunTest", output) || occursin("dry", lowercase(output))
            end
        end
    end

    @testset "@main Function End-to-End Integration" begin
        # Note: @main function is tested separately via CLI tests (test_cli.jl)
        # which uses julia -m to invoke the actual @main entry point.
        # Direct invocation of @main macro is not possible in tests.

        @testset "Dispatch command integration works end-to-end" begin
            # Test: Full dispatch flow without @main
            mktempdir() do tmpdir
                # Simulate what @main would do
                settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()
                JuliaPkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)

                parsed_args = ArgParse.parse_args(["create", "TestE2E", "--output-dir", tmpdir], settings)

                command = parsed_args["%COMMAND%"]
                result = JuliaPkgTemplatesCommandLineInterface.dispatch_command(command, parsed_args[command])

                @test result.success == true
                @test isdir(joinpath(tmpdir, "TestE2E"))
            end
        end
    end
end
