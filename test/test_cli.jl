"""
Tests for CLI argument parser

Task 4.1: CLI Argument Parser Construction
- ArgParse.jl ArgParseSettings configuration
- Subcommand definitions (create, config, plugin-info, completion)
- Global options (--version, --verbose, --dry-run)
- Dynamic plugin option generation
"""

using Test
using JuliaPkgTemplatesCommandLineInterface
using ArgParse

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

        # Verify existence of --verbose and --dry-run options by parsing
        parsed = parse_args(["--verbose", "create", "Pkg"], settings)
        @test parsed["verbose"] == true
        @test parsed["dry-run"] == false  # false since not specified
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
end
