using Test
using ArgParse
using PkgTemplatesCommandLineInterface
import PkgTemplatesCommandLineInterface.CreateCommand

@testset "CreateCommand Tests" begin
    @testset "merge_config" begin
        @testset "CLI arguments override config defaults" begin
            config_defaults = Dict{String, Any}(
                "author" => "Default Author",
                "user" => "default_user",
                "mail" => "default@example.com"
            )
            cli_args = Dict{String, Any}(
                "author" => "CLI Author",
                "user" => nothing  # Should not override
            )

            merged = CreateCommand.merge_config(config_defaults, cli_args)

            @test merged["author"] == "CLI Author"  # CLI overrides
            @test merged["user"] == "default_user"  # Config preserved (CLI was nothing)
            @test merged["mail"] == "default@example.com"  # Config preserved (not in CLI)
        end

        @testset "nested configuration merge" begin
            config_defaults = Dict{String, Any}(
                "formatter" => Dict{String, Any}(
                    "style" => "blue",
                    "indent" => 4
                )
            )
            cli_args = Dict{String, Any}(
                "formatter" => Dict{String, Any}(
                    "style" => "yas"
                )
            )

            merged = CreateCommand.merge_config(config_defaults, cli_args)

            @test merged["formatter"]["style"] == "yas"  # CLI overrides
            @test merged["formatter"]["indent"] == 4  # Config preserved
        end

        @testset "empty CLI args preserves all config" begin
            config_defaults = Dict{String, Any}(
                "author" => "Test",
                "user" => "testuser"
            )
            cli_args = Dict{String, Any}()

            merged = CreateCommand.merge_config(config_defaults, cli_args)

            @test merged == config_defaults
        end
    end

    @testset "parse_plugin_option_value" begin
        @testset "boolean values" begin
            @test CreateCommand.parse_plugin_option_value("ssh=true") == ("ssh", true)
            @test CreateCommand.parse_plugin_option_value("ssh=false") == ("ssh", false)
        end

        @testset "integer values" begin
            @test CreateCommand.parse_plugin_option_value("indent=4") == ("indent", 4)
            @test CreateCommand.parse_plugin_option_value("count=123") == ("count", 123)
        end

        @testset "float values" begin
            @test CreateCommand.parse_plugin_option_value("version=1.5") == ("version", 1.5)
            @test CreateCommand.parse_plugin_option_value("ratio=0.75") == ("ratio", 0.75)
        end

        @testset "string values" begin
            @test CreateCommand.parse_plugin_option_value("style=blue") == ("style", "blue")
            @test CreateCommand.parse_plugin_option_value("name=MyPkg") == ("name", "MyPkg")
        end

        @testset "array values" begin
            key, val = CreateCommand.parse_plugin_option_value("items=[a,b,c]")
            @test key == "items"
            @test val == ["a", "b", "c"]
        end
    end

    @testset "parse_plugin_options" begin
        # ArgParse stores plugin options under the lowercase plugin name
        # (no "--" prefix) and, with `nargs='?', constant=""`, the value is
        # one of: nothing (not supplied), "" (--<plugin> with no value), or
        # a single space-separated KEY=VALUE string.

        @testset "single plugin with multiple options" begin
            args = Dict{String, Any}(
                "git" => "ssh=true manifest=false",
                "package_name" => "MyPkg"
            )

            plugin_options = CreateCommand.parse_plugin_options(args)

            @test haskey(plugin_options, "Git")
            @test plugin_options["Git"]["ssh"] == true
            @test plugin_options["Git"]["manifest"] == false
        end

        @testset "multiple plugins" begin
            args = Dict{String, Any}(
                "git" => "ssh=true",
                "formatter" => "style=blue indent=4"
            )

            plugin_options = CreateCommand.parse_plugin_options(args)

            @test haskey(plugin_options, "Git")
            @test haskey(plugin_options, "Formatter")
            @test plugin_options["Git"]["ssh"] == true
            @test plugin_options["Formatter"]["style"] == "blue"
            @test plugin_options["Formatter"]["indent"] == 4
        end

        @testset "argumentless --plugin enables with empty section" begin
            # `--git` with no value parses to `args["git"] = ""` (the
            # `:constant`). parse_plugin_options must record this as
            # "enable Git with default options".
            args = Dict{String, Any}(
                "git" => "",
                "package_name" => "MyPkg"
            )

            plugin_options = CreateCommand.parse_plugin_options(args)

            @test haskey(plugin_options, "Git")
            @test plugin_options["Git"] == Dict{String,Any}()
        end

        @testset "skips plugin keys that ArgParse left at default (nothing)" begin
            # Plugin keys that the user did not pass arrive as `nothing`
            # (the `:default`). They must not appear in plugin_options.
            args = Dict{String, Any}(
                "git" => "ssh=true",
                "formatter" => nothing,
                "package_name" => "MyPkg"
            )

            plugin_options = CreateCommand.parse_plugin_options(args)

            @test haskey(plugin_options, "Git")
            @test !haskey(plugin_options, "Formatter")
        end

        @testset "ignores non-plugin keys" begin
            args = Dict{String, Any}(
                "git" => "ssh=true",
                "package_name" => "MyPkg",
                "author" => "Test Author"
            )

            plugin_options = CreateCommand.parse_plugin_options(args)

            @test length(keys(plugin_options)) == 1
            @test haskey(plugin_options, "Git")
        end
    end

    # Note: dry-run mode and error handling are tested in test_integration.jl

    # Helper: run `create --dry-run` against a temporary XDG config home that
    # already contains the supplied [default] section, capture stdout, and
    # return (result, output_string). Restores XDG_CONFIG_HOME on exit.
    function _dry_run_with_config(default_config::Dict{String,Any}, cli_args::Dict{String,Any})
        config_dir = mktempdir()
        out_dir = mktempdir()
        original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)
        try
            ENV["XDG_CONFIG_HOME"] = config_dir
            ConfigManager = PkgTemplatesCommandLineInterface.ConfigManager
            ConfigManager.save_config(Dict{String,Any}("default" => default_config))

            args = Dict{String,Any}(
                "package_name" => "ContractPkg",
                "output-dir" => out_dir,
                "dry-run" => true,
            )
            merge!(args, cli_args)

            pipe = Pipe()
            result = redirect_stdout(pipe) do
                CreateCommand.execute(args)
            end
            close(pipe.in)
            output = read(pipe.out, String)
            close(pipe.out)
            return result, output
        finally
            if original_xdg === nothing
                delete!(ENV, "XDG_CONFIG_HOME")
            else
                ENV["XDG_CONFIG_HOME"] = original_xdg
            end
            rm(config_dir; recursive=true, force=true)
            rm(out_dir; recursive=true, force=true)
        end
    end

    # Contract: shapes that `config set` writes to the [default] section reach
    # `PkgTemplates.Template` in a form the constructor accepts. Each test
    # below corresponds to a fix from the codex/Copilot review cycle and
    # protects against the same class of bug returning.
    @testset "execute() consumes config defaults" begin
        @testset "Vector author flows as authors=Vector{String}" begin
            # Regression: `[author]` over a Vector produced Vector{Vector{String}}
            # and PkgTemplates rejected it.
            result, out = _dry_run_with_config(
                Dict{String,Any}("author" => ["Alice", "Bob"]),
                Dict{String,Any}(),
            )
            @test result.success == true
            @test occursin("authors", out)
            @test occursin("Alice", out) && occursin("Bob", out)
            # Authors field must NOT be a nested vector representation
            @test !occursin("[[\"Alice\"", out)
        end

        @testset "mail appended only when author lacks <email>" begin
            # Author without email gets `<mail>` appended; an author that
            # already carries `<...>` is left untouched.
            result, out = _dry_run_with_config(
                Dict{String,Any}(
                    "author" => ["Alice", "Bob <bob@elsewhere.io>"],
                    "mail" => "team@example.com",
                ),
                Dict{String,Any}(),
            )
            @test result.success == true
            @test occursin("Alice <team@example.com>", out)
            @test occursin("Bob <bob@elsewhere.io>", out)
            @test !occursin("Bob <team@example.com>", out)
        end

        @testset "license_type promoted to License plugin" begin
            # license_type is the persistence key; create must lift it into
            # plugin_options["License"] so PackageGenerator picks it up.
            result, out = _dry_run_with_config(
                Dict{String,Any}("license_type" => "MIT"),
                Dict{String,Any}(),
            )
            @test result.success == true
            @test occursin("Plugin: License", out)
            @test occursin("name = MIT", out)
        end

        @testset "explicit CLI License plugin overrides license_type promotion" begin
            # The license_type → License-plugin promotion is guarded by
            # `!haskey(plugin_options, "License")` so a CLI-supplied License
            # keeps precedence. With issue #7 resolved, parse_plugin_options
            # consumes the real ArgParse shape: lowercase plugin name keys
            # carrying a single space-separated KEY=VALUE string.
            result, out = _dry_run_with_config(
                Dict{String,Any}("license_type" => "MIT"),
                Dict{String,Any}("license" => "name=Apache"),
            )
            @test result.success == true
            # CLI value wins; the config license_type must not be applied.
            @test occursin("name = Apache", out)
            @test !occursin("name = MIT", out)
        end

        @testset "--with-mise CLI overrides config with_mise=false" begin
            # CLI flags arrive under "with-mise"/"no-mise" (dashes); the
            # persisted key is "with_mise" (underscore). Without normalization
            # the explicit override is silently ignored.
            result, out = _dry_run_with_config(
                Dict{String,Any}("with_mise" => false),
                Dict{String,Any}("with-mise" => true),
            )
            @test result.success == true
            @test occursin("with_mise = true", out)
        end

        @testset "--no-mise CLI overrides config with_mise=true" begin
            result, out = _dry_run_with_config(
                Dict{String,Any}("with_mise" => true),
                Dict{String,Any}("no-mise" => true),
            )
            @test result.success == true
            @test occursin("with_mise = false", out)
        end

        @testset "dotted plugin defaults reach create as plugin options" begin
            # Regression: `formatter.style => blue` used to be persisted under
            # the literal lowercase `formatter` key, but create only treats
            # capitalized sections as plugin options. Section canonicalization
            # closes the loop so dot-notation defaults end up as Plugin options.
            result, out = _dry_run_with_config(
                Dict{String,Any}(
                    "Formatter" => Dict{String,Any}("style" => "blue"),
                ),
                Dict{String,Any}(),
            )
            @test result.success == true
            @test occursin("Plugin: Formatter", out)
            @test occursin("style = blue", out)
        end
    end

    # Contract: real CLI argv strings flow through ArgParse, parse_plugin_options,
    # and reach the dry-run plan. This is the issue #7 regression net — the
    # earlier synthetic-arg tests passed even though the production CLI path
    # silently dropped every plugin option.
    @testset "create CLI plugin options reach PackageGenerator (issue #7)" begin
        # Helper: parse `argv` against the real `jtc` settings tree and run
        # `CreateCommand.execute` against an empty XDG config so config
        # defaults cannot mask CLI inputs. Returns (result, captured stdout).
        function _e2e_dry_run(argv::Vector{String})
            config_dir = mktempdir()
            out_dir = mktempdir()
            original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)
            try
                ENV["XDG_CONFIG_HOME"] = config_dir

                settings = PkgTemplatesCommandLineInterface.create_argument_parser()
                PkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)

                full_argv = vcat(argv, ["--output-dir", out_dir, "--dry-run"])
                parsed = ArgParse.parse_args(full_argv, settings)
                @assert parsed["%COMMAND%"] == "create"
                sub_args = parsed["create"]

                pipe = Pipe()
                result = redirect_stdout(pipe) do
                    CreateCommand.execute(sub_args)
                end
                close(pipe.in)
                output = read(pipe.out, String)
                close(pipe.out)
                return result, output
            finally
                if original_xdg === nothing
                    delete!(ENV, "XDG_CONFIG_HOME")
                else
                    ENV["XDG_CONFIG_HOME"] = original_xdg
                end
                rm(config_dir; recursive=true, force=true)
                rm(out_dir; recursive=true, force=true)
            end
        end

        @testset "--git \"ssh=true manifest=false\" populates Git plugin options" begin
            result, out = _e2e_dry_run(
                ["create", "E2EPkg", "--user", "u", "--git", "ssh=true manifest=false"],
            )
            @test result.success == true
            @test occursin("Plugin: Git", out)
            @test occursin("ssh = true", out)
            @test occursin("manifest = false", out)
        end

        @testset "--readme (no value) enables Readme with default options" begin
            result, out = _e2e_dry_run(
                ["create", "E2EPkg", "--user", "u", "--readme"],
            )
            @test result.success == true
            @test occursin("Plugin: Readme", out)
        end

        @testset "--license overrides config license_type via CLI path" begin
            # Seed config with license_type=MIT, then assert CLI --license wins.
            config_dir = mktempdir()
            out_dir = mktempdir()
            original_xdg = get(ENV, "XDG_CONFIG_HOME", nothing)
            try
                ENV["XDG_CONFIG_HOME"] = config_dir
                ConfigManager = PkgTemplatesCommandLineInterface.ConfigManager
                ConfigManager.save_config(Dict{String,Any}(
                    "default" => Dict{String,Any}("license_type" => "MIT"),
                ))

                settings = PkgTemplatesCommandLineInterface.create_argument_parser()
                PkgTemplatesCommandLineInterface.add_dynamic_plugin_options!(settings)
                argv = ["create", "E2EPkg", "--user", "u",
                        "--license", "name=Apache",
                        "--output-dir", out_dir, "--dry-run"]
                parsed = ArgParse.parse_args(argv, settings)

                pipe = Pipe()
                result = redirect_stdout(pipe) do
                    CreateCommand.execute(parsed["create"])
                end
                close(pipe.in)
                output = read(pipe.out, String)
                close(pipe.out)

                @test result.success == true
                @test occursin("name = Apache", output)
                @test !occursin("name = MIT", output)
            finally
                if original_xdg === nothing
                    delete!(ENV, "XDG_CONFIG_HOME")
                else
                    ENV["XDG_CONFIG_HOME"] = original_xdg
                end
                rm(config_dir; recursive=true, force=true)
                rm(out_dir; recursive=true, force=true)
            end
        end

        @testset "no plugin args yields empty plugin_options" begin
            result, out = _e2e_dry_run(
                ["create", "E2EPkg", "--user", "u"],
            )
            @test result.success == true
            # The dry-run prints "Plugin options:" once, then nothing under
            # it when no plugins were selected. Asserting absence of any
            # "Plugin: " line is the cleanest way to confirm.
            @test !occursin("Plugin: ", out)
        end
    end
end
