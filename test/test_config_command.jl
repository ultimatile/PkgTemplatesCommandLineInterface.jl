"""
Tests for ConfigCommand module.

Tests config show/set subcommands, configuration formatting,
and update logic.
"""

using Test
using PkgTemplatesCommandLineInterface
using TOML

# Import ConfigCommand from the main module
using PkgTemplatesCommandLineInterface.ConfigCommand

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

            # Dotted plugin names land under their canonical PkgTemplates form
            # (`Git`, not `git`) so CreateCommand picks them up as a plugin.
            @test haskey(updated["default"], "Git")
            @test updated["default"]["Git"]["manifest"] == true
            @test updated["default"]["Git"]["ssh"] == false
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

    # Contract: parse_plugin_option_value preserves the user's intent across
    # types — bools, ints, decimals (kept as strings so VersionNumber survives),
    # bracket arrays, comma-promoted arrays, and quoted strings.
    @testset "parse_plugin_option_value contracts" begin
        @testset "boolean synonyms cover true/yes/false/no but not 0/1" begin
            @test ConfigCommand.parse_plugin_option_value("true") === true
            @test ConfigCommand.parse_plugin_option_value("YES") === true
            @test ConfigCommand.parse_plugin_option_value("false") === false
            @test ConfigCommand.parse_plugin_option_value("No") === false
            # `1`/`0` must round-trip as integers so plugin int options like
            # `indent=1` don't become booleans.
            @test ConfigCommand.parse_plugin_option_value("1") === 1
            @test ConfigCommand.parse_plugin_option_value("0") === 0
        end

        @testset "integer values keep their type" begin
            @test ConfigCommand.parse_plugin_option_value("42") === 42
            @test ConfigCommand.parse_plugin_option_value("100") === 100
        end

        @testset "decimal-shaped values stay strings" begin
            # ProjectFile.version expects a string parseable into VersionNumber;
            # Float coercion both breaks the constructor and loses trailing zeros.
            @test ConfigCommand.parse_plugin_option_value("1.10") == "1.10"
            @test ConfigCommand.parse_plugin_option_value("1.10") isa AbstractString
            @test ConfigCommand.parse_plugin_option_value("1.2") == "1.2"
        end

        @testset "bracket-form arrays parse to Vector{String}" begin
            @test ConfigCommand.parse_plugin_option_value("[a,b,c]") == ["a", "b", "c"]
            @test ConfigCommand.parse_plugin_option_value("[]") == String[]
            # Quoted items inside brackets keep their internal text
            @test ConfigCommand.parse_plugin_option_value("[\"a b\",c]") == ["a b", "c"]
        end

        @testset "unquoted comma values promote to arrays" begin
            @test ConfigCommand.parse_plugin_option_value("a,b,c") == ["a", "b", "c"]
            @test ConfigCommand.parse_plugin_option_value(".DS_Store,.vscode") ==
                  [".DS_Store", ".vscode"]
        end

        @testset "quoted strings keep commas as literal text" begin
            # Without this contract, Git.name="Doe, Jane" silently becomes a
            # Vector{String} and the plugin constructor fails.
            @test ConfigCommand.parse_plugin_option_value("\"Doe, Jane\"") == "Doe, Jane"
            @test ConfigCommand.parse_plugin_option_value("'a, b, c'") == "a, b, c"
        end

        @testset "plain strings flow through unchanged" begin
            @test ConfigCommand.parse_plugin_option_value("blue") == "blue"
            @test ConfigCommand.parse_plugin_option_value("MyPkg") == "MyPkg"
        end
    end

    # Contract: ConfigCommand.execute accepts both legacy flat dicts and the
    # ArgParse-shaped nested dict, and writes the same values either way.
    @testset "execute() ArgParse-shape contracts" begin
        @testset "nested args dict round-trips set then show" begin
            tmpdir = mktempdir()
            try
                custom_path = joinpath(tmpdir, "nested.toml")
                set_args = Dict{String,Any}(
                    "%COMMAND%" => "set",
                    "set" => Dict{String,Any}(
                        "author" => Any["Alice"],
                        "user" => "alice",
                        "config-file" => custom_path,
                    ),
                )
                @test ConfigCommand.execute(set_args).success == true
                @test isfile(custom_path)

                show_args = Dict{String,Any}(
                    "%COMMAND%" => "show",
                    "show" => Dict{String,Any}("config-file" => custom_path),
                )
                pipe = Pipe()
                result = redirect_stdout(pipe) do
                    ConfigCommand.execute(show_args)
                end
                close(pipe.in)
                output = read(pipe.out, String)
                close(pipe.out)
                @test result.success == true
                @test occursin("Alice", output)
                @test occursin("alice", output)
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end

        @testset "repeated --author becomes Vector{String}" begin
            tmpdir = mktempdir()
            try
                custom_path = joinpath(tmpdir, "vec.toml")
                set_args = Dict{String,Any}(
                    "%COMMAND%" => "set",
                    "set" => Dict{String,Any}(
                        "author" => Any["Alice", "Bob"],
                        "config-file" => custom_path,
                    ),
                )
                @test ConfigCommand.execute(set_args).success == true
                cfg = TOML.parsefile(custom_path)
                @test cfg["default"]["author"] == ["Alice", "Bob"]
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end

        @testset "--no-mise persists with_mise=false (not literal with-mise)" begin
            tmpdir = mktempdir()
            try
                custom_path = joinpath(tmpdir, "mise.toml")
                set_args = Dict{String,Any}(
                    "%COMMAND%" => "set",
                    "set" => Dict{String,Any}(
                        "no-mise" => true,
                        "with-mise" => false,
                        "config-file" => custom_path,
                    ),
                )
                @test ConfigCommand.execute(set_args).success == true
                cfg = TOML.parsefile(custom_path)
                @test cfg["default"]["with_mise"] === false
                # Don't pollute the config with the dashed CLI keys.
                @test !haskey(cfg["default"], "with-mise")
                @test !haskey(cfg["default"], "no-mise")
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end

        @testset "lowercase plugin keys map to canonical PkgTemplates names" begin
            tmpdir = mktempdir()
            try
                custom_path = joinpath(tmpdir, "plugin.toml")
                set_args = Dict{String,Any}(
                    "%COMMAND%" => "set",
                    "set" => Dict{String,Any}(
                        "git" => "ssh=true",
                        "config-file" => custom_path,
                    ),
                )
                @test ConfigCommand.execute(set_args).success == true
                cfg = TOML.parsefile(custom_path)
                # Stored under the canonical capitalized name PkgTemplates expects
                @test haskey(cfg["default"], "Git")
                @test cfg["default"]["Git"]["ssh"] === true
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end

        @testset "quoted plugin string values stay strings" begin
            tmpdir = mktempdir()
            try
                custom_path = joinpath(tmpdir, "quote.toml")
                set_args = Dict{String,Any}(
                    "%COMMAND%" => "set",
                    "set" => Dict{String,Any}(
                        "git" => "name=\"Doe, Jane\"",
                        "config-file" => custom_path,
                    ),
                )
                @test ConfigCommand.execute(set_args).success == true
                cfg = TOML.parsefile(custom_path)
                @test cfg["default"]["Git"]["name"] == "Doe, Jane"
                @test cfg["default"]["Git"]["name"] isa AbstractString
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end

        @testset "config-file is not persisted as a [default] entry" begin
            # Direct callers may pass only `config-file` to redirect the
            # destination; that key must never end up under [default].
            tmpdir = mktempdir()
            try
                custom_path = joinpath(tmpdir, "redirect.toml")
                args = Dict{String,Any}(
                    "%SUBCOMMAND%" => "set",
                    "config-file" => custom_path,
                    "formatter.style" => "blue",
                )
                @test ConfigCommand.execute(args).success == true
                cfg = TOML.parsefile(custom_path)
                @test !haskey(cfg["default"], "config-file")
                @test cfg["default"]["Formatter"]["style"] == "blue"
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end

        @testset "mixed flat dict (CLI key + dotted key) round-trips both" begin
            # Direct callers still pass the legacy flat shape; the dotted key
            # used to be silently dropped once the CLI-style branch was taken.
            test_dir = mktempdir()
            original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)
            try
                ENV["XDG_CONFIG_HOME"] = test_dir
                args = Dict{String,Any}(
                    "%SUBCOMMAND%" => "set",
                    "author" => "A",
                    "formatter.style" => "blue",
                )
                @test ConfigCommand.execute(args).success == true
                cfg = ConfigCommand.ConfigManager.load_config()
                @test cfg["default"]["author"] == "A"
                # Section name is canonicalized so the entry is reachable by
                # CreateCommand's plugin extraction.
                @test cfg["default"]["Formatter"]["style"] == "blue"
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
end
