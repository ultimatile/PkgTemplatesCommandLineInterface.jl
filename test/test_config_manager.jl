"""
Tests for ConfigManager module.

Tests XDG Base Directory compliance, TOML file operations,
default config generation, and nested configuration support.
"""

using Test
using JuliaPkgTemplatesCommandLineInterface
using TOML

# Import ConfigManager (will be defined in src/config_manager.jl)
include("../src/config_manager.jl")

@testset "ConfigManager" begin
    @testset "get_config_path()" begin
        @testset "respects XDG_CONFIG_HOME when set" begin
            # Save original value
            original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)

            try
                # Test with custom XDG_CONFIG_HOME
                test_dir = mktempdir()
                ENV["XDG_CONFIG_HOME"] = test_dir

                config_path = ConfigManager.get_config_path()

                @test startswith(config_path, test_dir)
                @test endswith(config_path, joinpath("jtc", "config.toml"))
                @test isdir(dirname(config_path))  # Directory should be created
            finally
                # Restore original value
                if original_xdg === nothing
                    delete!(ENV, "XDG_CONFIG_HOME")
                else
                    ENV["XDG_CONFIG_HOME"] = original_xdg
                end
            end
        end

        @testset "uses ~/.config when XDG_CONFIG_HOME not set" begin
            # Save original value
            original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)

            try
                # Ensure XDG_CONFIG_HOME is not set
                if haskey(ENV, "XDG_CONFIG_HOME")
                    delete!(ENV, "XDG_CONFIG_HOME")
                end

                config_path = ConfigManager.get_config_path()
                expected_path = joinpath(homedir(), ".config", "jtc", "config.toml")

                @test config_path == expected_path
            finally
                # Restore original value
                if original_xdg !== nothing
                    ENV["XDG_CONFIG_HOME"] = original_xdg
                end
            end
        end

        @testset "creates directory if it doesn't exist" begin
            test_dir = mktempdir()
            original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)

            try
                ENV["XDG_CONFIG_HOME"] = test_dir
                config_path = ConfigManager.get_config_path()

                @test isdir(dirname(config_path))
            finally
                if original_xdg === nothing
                    delete!(ENV, "XDG_CONFIG_HOME")
                else
                    ENV["XDG_CONFIG_HOME"] = original_xdg
                end
                rm(test_dir; recursive=true, force=true)
            end
        end
    end

    @testset "create_default_config()" begin
        config = ConfigManager.create_default_config()

        @test haskey(config, "default")
        @test haskey(config["default"], "author")
        @test haskey(config["default"], "user")
        @test haskey(config["default"], "mail")
        @test haskey(config["default"], "mise_filename_base")
        @test haskey(config["default"], "with_mise")

        @test config["default"]["author"] == ""
        @test config["default"]["user"] == ""
        @test config["default"]["mail"] == ""
        @test config["default"]["mise_filename_base"] == ".mise"
        @test config["default"]["with_mise"] == true
    end

    @testset "save_config() and load_config()" begin
        test_dir = mktempdir()
        original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)

        try
            ENV["XDG_CONFIG_HOME"] = test_dir

            @testset "save_config() creates valid TOML file with sorted keys" begin
                test_config = Dict{String,Any}(
                    "default" => Dict{String,Any}(
                        "author" => "Test Author",
                        "user" => "testuser",
                        "mail" => "test@example.com",
                        "mise_filename_base" => ".mise",
                        "with_mise" => true
                    )
                )

                ConfigManager.save_config(test_config)

                config_path = ConfigManager.get_config_path()
                @test isfile(config_path)

                # Verify TOML is valid
                saved_config = TOML.parsefile(config_path)
                @test saved_config["default"]["author"] == "Test Author"
                @test saved_config["default"]["user"] == "testuser"
            end

            @testset "load_config() reads existing file" begin
                # Config file was created in previous test
                loaded_config = ConfigManager.load_config()

                @test haskey(loaded_config, "default")
                @test loaded_config["default"]["author"] == "Test Author"
                @test loaded_config["default"]["user"] == "testuser"
            end

            @testset "load_config() creates default when file doesn't exist" begin
                # Delete existing config
                config_path = ConfigManager.get_config_path()
                rm(config_path; force=true)

                loaded_config = ConfigManager.load_config()

                # Should return default config
                @test haskey(loaded_config, "default")
                @test loaded_config["default"]["author"] == ""
                @test loaded_config["default"]["user"] == ""

                # Should create the file
                @test isfile(config_path)
            end

            @testset "load_config() handles parse errors gracefully" begin
                # Write invalid TOML
                config_path = ConfigManager.get_config_path()
                write(config_path, "invalid toml {{{")

                # Should return default config and emit expected logs
                loaded_config = @test_logs (:error,) (:warn,) ConfigManager.load_config()

                @test haskey(loaded_config, "default")
                @test loaded_config["default"]["author"] == ""
            end

            @testset "supports nested configuration" begin
                nested_config = Dict{String,Any}(
                    "default" => Dict{String,Any}(
                        "author" => "Test",
                        "formatter" => Dict{String,Any}(
                            "style" => "blue"
                        ),
                        "git" => Dict{String,Any}(
                            "manifest" => true,
                            "ssh" => false
                        )
                    )
                )

                ConfigManager.save_config(nested_config)
                loaded_config = ConfigManager.load_config()

                @test haskey(loaded_config["default"], "formatter")
                @test loaded_config["default"]["formatter"]["style"] == "blue"
                @test haskey(loaded_config["default"], "git")
                @test loaded_config["default"]["git"]["manifest"] == true
                @test loaded_config["default"]["git"]["ssh"] == false
            end
        finally
            if original_xdg === nothing
                delete!(ENV, "XDG_CONFIG_HOME")
            else
                ENV["XDG_CONFIG_HOME"] = original_xdg
            end
            rm(test_dir; recursive=true, force=true)
        end
    end

    @testset "merge_config()" begin
        @testset "CLI arguments override config defaults" begin
            config_defaults = Dict{String,Any}(
                "author" => "Default Author",
                "user" => "defaultuser",
                "mail" => "default@example.com"
            )

            cli_args = Dict{String,Any}(
                "author" => "CLI Author",
                "user" => nothing,  # Should not override
                "extra" => "new value"
            )

            merged = ConfigManager.merge_config(config_defaults, cli_args)

            @test merged["author"] == "CLI Author"  # CLI overrides
            @test merged["user"] == "defaultuser"  # Default preserved (nothing doesn't override)
            @test merged["mail"] == "default@example.com"  # Default preserved
            @test merged["extra"] == "new value"  # New key added
        end

        @testset "merges nested configurations" begin
            config_defaults = Dict{String,Any}(
                "formatter" => Dict{String,Any}(
                    "style" => "blue",
                    "indent" => 4
                )
            )

            cli_args = Dict{String,Any}(
                "formatter" => Dict{String,Any}(
                    "style" => "yas"  # Override style, keep indent
                )
            )

            merged = ConfigManager.merge_config(config_defaults, cli_args)

            @test merged["formatter"]["style"] == "yas"  # Overridden
            @test merged["formatter"]["indent"] == 4  # Preserved from default
        end

        @testset "handles empty inputs" begin
            # Empty config
            merged = ConfigManager.merge_config(Dict{String,Any}(), Dict{String,Any}("key" => "value"))
            @test merged["key"] == "value"

            # Empty CLI args
            merged = ConfigManager.merge_config(Dict{String,Any}("key" => "value"), Dict{String,Any}())
            @test merged["key"] == "value"
        end
    end
end
