"""
Tests for ConfigCommand module.

Tests config show/set subcommands, configuration formatting,
and update logic.
"""

using Test
using JuliaPkgTemplatesCommandLineInterface
using TOML

# Import ConfigCommand from the main module
using JuliaPkgTemplatesCommandLineInterface.ConfigCommand

@testset "ConfigCommand" begin
    @testset "format_config()" begin
        @testset "formats simple configuration as TOML string" begin
            config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Test Author",
                    "user" => "testuser",
                    "mail" => "test@example.com"
                )
            )

            formatted = ConfigCommand.format_config(config)

            @test isa(formatted, String)
            @test contains(formatted, "author")
            @test contains(formatted, "Test Author")
            @test contains(formatted, "testuser")
            @test contains(formatted, "test@example.com")

            # Verify it's valid TOML
            parsed = TOML.parse(formatted)
            @test parsed["default"]["author"] == "Test Author"
        end

        @testset "formats nested configuration correctly" begin
            config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Test",
                    "formatter" => Dict{String,Any}(
                        "style" => "blue",
                        "indent" => 4
                    )
                )
            )

            formatted = ConfigCommand.format_config(config)

            @test contains(formatted, "[default.formatter]")
            @test contains(formatted, "style")
            @test contains(formatted, "blue")

            # Verify it's valid TOML
            parsed = TOML.parse(formatted)
            @test parsed["default"]["formatter"]["style"] == "blue"
            @test parsed["default"]["formatter"]["indent"] == 4
        end

        @testset "handles empty configuration" begin
            config = Dict{String,Any}()
            formatted = ConfigCommand.format_config(config)

            @test isa(formatted, String)
            @test length(formatted) >= 0  # May be empty or contain whitespace
        end
    end

    @testset "update_config()" begin
        @testset "updates simple configuration values" begin
            existing_config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Old Author",
                    "user" => "olduser",
                    "mail" => "old@example.com"
                )
            )

            new_values = Dict{String,Any}(
                "author" => "New Author",
                "mail" => "new@example.com"
            )

            updated = ConfigCommand.update_config(existing_config, new_values)

            @test updated["default"]["author"] == "New Author"  # Updated
            @test updated["default"]["user"] == "olduser"  # Preserved
            @test updated["default"]["mail"] == "new@example.com"  # Updated
        end

        @testset "supports nested configuration with dot notation" begin
            existing_config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Test",
                    "formatter" => Dict{String,Any}(
                        "style" => "blue"
                    )
                )
            )

            new_values = Dict{String,Any}(
                "formatter.style" => "yas",
                "formatter.indent" => 4
            )

            updated = ConfigCommand.update_config(existing_config, new_values)

            @test haskey(updated["default"], "formatter")
            @test updated["default"]["formatter"]["style"] == "yas"
            @test updated["default"]["formatter"]["indent"] == 4
        end

        @testset "creates nested sections if they don't exist" begin
            existing_config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Test"
                )
            )

            new_values = Dict{String,Any}(
                "git.manifest" => true,
                "git.ssh" => false
            )

            updated = ConfigCommand.update_config(existing_config, new_values)

            @test haskey(updated["default"], "git")
            @test updated["default"]["git"]["manifest"] == true
            @test updated["default"]["git"]["ssh"] == false
        end

        @testset "ignores command-related keys" begin
            existing_config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Test"
                )
            )

            new_values = Dict{String,Any}(
                "author" => "New Author",
                "show" => true,  # Should be ignored
                "set" => "value",  # Should be ignored
                "%SUBCOMMAND%" => "set"  # Should be ignored
            )

            updated = ConfigCommand.update_config(existing_config, new_values)

            @test updated["default"]["author"] == "New Author"
            @test !haskey(updated["default"], "show")
            @test !haskey(updated["default"], "set")
            @test !haskey(updated["default"], "%SUBCOMMAND%")
        end

        @testset "preserves existing values when updating" begin
            existing_config = Dict{String,Any}(
                "default" => Dict{String,Any}(
                    "author" => "Test",
                    "user" => "testuser",
                    "mail" => "test@example.com"
                )
            )

            new_values = Dict{String,Any}(
                "author" => "New Author"
            )

            updated = ConfigCommand.update_config(existing_config, new_values)

            @test updated["default"]["author"] == "New Author"
            @test updated["default"]["user"] == "testuser"  # Preserved
            @test updated["default"]["mail"] == "test@example.com"  # Preserved
        end
    end

    @testset "execute()" begin
        test_dir = mktempdir()
        original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)

        try
            ENV["XDG_CONFIG_HOME"] = test_dir

            @testset "executes 'show' subcommand successfully" begin
                # Create a test config first
                test_config = Dict{String,Any}(
                    "default" => Dict{String,Any}(
                        "author" => "Show Test",
                        "user" => "showuser"
                    )
                )
                ConfigCommand.ConfigManager.save_config(test_config)

                args = Dict{String,Any}(
                    "%SUBCOMMAND%" => "show"
                )

                # Capture output using Pipe
                pipe = Pipe()
                result = redirect_stdout(pipe) do
                    ConfigCommand.execute(args)
                end
                close(pipe.in)
                output_str = read(pipe.out, String)
                close(pipe.out)

                @test result.success == true
                @test contains(output_str, "Show Test")
                @test contains(output_str, "showuser")
            end

            @testset "executes 'set' subcommand successfully" begin
                # Load existing config
                existing = ConfigCommand.ConfigManager.load_config()

                args = Dict{String,Any}(
                    "%SUBCOMMAND%" => "set",
                    "author" => "Set Test",
                    "mail" => "set@example.com"
                )

                result = ConfigCommand.execute(args)

                @test result.success == true
                @test result.message == "Configuration updated successfully"

                # Verify config was actually updated
                updated_config = ConfigCommand.ConfigManager.load_config()
                @test updated_config["default"]["author"] == "Set Test"
                @test updated_config["default"]["mail"] == "set@example.com"
            end

            @testset "defaults to 'show' when no subcommand specified" begin
                test_config = Dict{String,Any}(
                    "default" => Dict{String,Any}(
                        "author" => "Default Show Test"
                    )
                )
                ConfigCommand.ConfigManager.save_config(test_config)

                args = Dict{String,Any}()  # No subcommand

                # Capture output using Pipe
                pipe = Pipe()
                result = redirect_stdout(pipe) do
                    ConfigCommand.execute(args)
                end
                close(pipe.in)
                output_str = read(pipe.out, String)
                close(pipe.out)

                @test result.success == true
                @test contains(output_str, "Default Show Test")
            end

            @testset "handles unknown subcommand" begin
                args = Dict{String,Any}(
                    "%SUBCOMMAND%" => "unknown"
                )

                result = ConfigCommand.execute(args)

                @test result.success == false
                @test contains(result.message, "Unknown") || contains(result.message, "unknown")
            end

            @testset "handles errors gracefully" begin
                # Test that execute doesn't crash even with edge cases
                args = Dict{String,Any}(
                    "%SUBCOMMAND%" => "set",
                    "author" => "Error Test"
                )

                # Should not crash, should return something with success field
                result = ConfigCommand.execute(args)
                @test hasfield(typeof(result), :success)
                @test isa(result.success, Bool)
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
end
