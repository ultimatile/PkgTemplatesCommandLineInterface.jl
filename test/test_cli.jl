"""
Tests for CLI argument parser

Task 4.1: CLI Argument Parser Construction
- ArgParse.jl ArgParseSettings configuration
- Subcommand definitions (create, config, plugin-info, completion)
- Global options (--version, --verbose)
- Dynamic plugin option generation
"""

using Test
using JuliaPkgTemplatesCommandLineInterface
using ArgParse
using TOML

@testset "CLI Argument Parser Tests" begin
    @testset "create_argument_parser - basic structure" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()

        @test settings isa ArgParseSettings
        @test settings.prog == "jtc"
        @test occursin("Julia package template generator", settings.description)
    end

    @testset "create_argument_parser - subcommand definitions" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()

        # Verify that subcommands are correctly defined
        @test haskey(settings, "create")
        @test haskey(settings, "config")
        @test haskey(settings, "plugin-info")
        @test haskey(settings, "completion")
    end

    @testset "create_argument_parser - global options" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()

        # --version option (automatically added by ArgParse with add_version=true)
        @test settings.add_version == true

        # Verify existence of --verbose option by parsing
        parsed = parse_args(["--verbose", "create", "Pkg"], settings)
        @test parsed["verbose"] == true
    end

    @testset "add_dynamic_plugin_options! - plugin option generation" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()

        # Add dynamic plugin options
        JuliaPkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)

        # Verify that plugin options are added to the create subcommand
        # Verify Git plugin option by parsing (standard plugin in PkgTemplates.jl)
        # Check subcommand existence with haskey
        @test haskey(settings, "create")

        # Verify that Git plugin option is correctly added by parsing
        # Git is a standard plugin in PkgTemplates.jl and should always exist
        parsed = parse_args(["create", "MyPackage", "--git"], settings)
        @test haskey(parsed["create"], "git")
    end

    @testset "parse_args - parsing create command" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()
        JuliaPkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)

        # Basic create command
        args = ["create", "MyPackage"]
        parsed = parse_args(args, settings)

        @test parsed["%COMMAND%"] == "create"
        @test parsed["create"]["package_name"] == "MyPackage"
    end

    @testset "parse_args - parsing global options" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()
        JuliaPkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)

        # With --verbose option
        args = ["--verbose", "create", "MyPackage"]
        parsed = parse_args(args, settings)

        @test parsed["verbose"] == true
        @test parsed["%COMMAND%"] == "create"
    end

    @testset "parse_args - --version option" begin
        settings = JuliaPkgTemplatesCommandLineInterface.create_argument_parser()

        # Since --version is automatically handled by ArgParse,
        # we verify that settings.add_version is true
        @test settings.add_version == true
        @test settings.version != ""
    end

    @testset "@main function - dispatch and error handling" begin
        # Test dispatch_command function
        @testset "dispatch_command - create command" begin
            mktempdir() do tmpdir
                args = Dict{String,Any}("package_name" => "TestPkg", "output-dir" => tmpdir)
                result = JuliaPkgTemplatesCommandLineInterface.dispatch_command("create", args)
                @test result isa JuliaPkgTemplatesCommandLineInterface.CommandResult
            end
        end

        @testset "dispatch_command - config command" begin
            args = Dict{String, Any}()
            result = JuliaPkgTemplatesCommandLineInterface.dispatch_command("config", args)
            @test result isa JuliaPkgTemplatesCommandLineInterface.CommandResult
        end

        @testset "dispatch_command - plugin-info command" begin
            args = Dict{String, Any}()
            result = JuliaPkgTemplatesCommandLineInterface.dispatch_command("plugin-info", args)
            @test result isa JuliaPkgTemplatesCommandLineInterface.CommandResult
        end

        @testset "dispatch_command - completion command" begin
            args = Dict{String,Any}("shell" => "fish")
            result = JuliaPkgTemplatesCommandLineInterface.dispatch_command("completion", args)
            @test result isa JuliaPkgTemplatesCommandLineInterface.CommandResult
        end

        @testset "dispatch_command - unknown command error" begin
            args = Dict{String, Any}()
            @test_throws ErrorException JuliaPkgTemplatesCommandLineInterface.dispatch_command("unknown", args)
        end
    end

    @testset "handle_error function" begin
        # Test error message conversion
        @testset "handle_error - JTCError types" begin
            err = JuliaPkgTemplatesCommandLineInterface.PackageGenerationError("Test error")
            result = JuliaPkgTemplatesCommandLineInterface.handle_error(err)
            @test result isa JuliaPkgTemplatesCommandLineInterface.CommandResult
            @test result.success == false
            @test occursin("Test error", result.message)
        end

        @testset "handle_error - generic Exception" begin
            err = ErrorException("Generic error")
            result = JuliaPkgTemplatesCommandLineInterface.handle_error(err)
            @test result isa JuliaPkgTemplatesCommandLineInterface.CommandResult
            @test result.success == false
            @test occursin("Generic error", result.message)
        end
    end

    @testset "Julia 1.12 Apps feature - Task 6.1" begin
        @testset "Apps configuration in Project.toml" begin
            # Verify that [apps.jtc] is configured in Project.toml
            project_file = joinpath(@__DIR__, "..", "Project.toml")
            project_data = TOML.parsefile(project_file)

            @test haskey(project_data, "apps")
            @test haskey(project_data["apps"], "jtc")
        end

        @testset "Apps invocation - --version" begin
            # Test Apps invocation via julia -m flag
            result = read(`$(Base.julia_cmd()) --project=. -m JuliaPkgTemplatesCommandLineInterface --version`, String)
            @test occursin(r"\d+\.\d+\.\d+", result)  # Version format: x.y.z
        end

        @testset "Apps invocation - help display" begin
            # Test Apps invocation with no arguments (should show help)
            # Note: ArgParse exits with non-zero when no command is given, so we catch the process failure
            proc = run(pipeline(`$(Base.julia_cmd()) --project=. -m JuliaPkgTemplatesCommandLineInterface`, stdout=devnull, stderr=devnull), wait=false)
            wait(proc)
            # ArgParse exits with error when no command given
            @test proc.exitcode != 0  # Expected behavior
        end

        @testset "Apps invocation - error handling" begin
            # Test Apps invocation with invalid arguments
            # Should return error message
            proc = run(pipeline(`$(Base.julia_cmd()) --project=. -m JuliaPkgTemplatesCommandLineInterface invalid-command`, stdout=devnull, stderr=devnull), wait=false)
            wait(proc)
            # Command exits with error as expected for invalid command
            @test proc.exitcode != 0  # Expected behavior
        end
    end
end
