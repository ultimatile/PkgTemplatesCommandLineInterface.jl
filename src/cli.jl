"""
CLI Layer: Argument parsing and command dispatch using ArgParse.jl

Task 4.1: CLI Argument Parser Construction
- ArgParse.jl `ArgParseSettings` configuration
- Subcommand definitions (create, config, plugin-info, completion)
- Global options (--version, --verbose, --dry-run)
- Dynamic plugin option generation
"""

using ArgParse
using PkgTemplates
using TOML

import Logging

"""
Create ArgParse settings object with subcommand definitions

# Returns
- `ArgParseSettings`: ArgParse.jl settings object

# Subcommands
- `create`: Create a new Julia package
- `config`: Configuration management (show/set)
- `plugin-info`: Display plugin information
- `completion`: Generate shell completion scripts
"""
function create_argument_parser()::ArgParseSettings
    s = ArgParseSettings(
        prog = "jtc",
        description = "Julia package template generator CLI",
        version = get_version(),
        add_version = true
    )

    @add_arg_table! s begin
        "create"
            action = :command
            help = "Create a new Julia package"
        "config"
            action = :command
            help = "Manage configuration"
        "plugin-info"
            action = :command
            help = "Show plugin information"
        "completion"
            action = :command
            help = "Generate shell completion scripts"
    end

    # Global options
    @add_arg_table! s begin
        "--verbose", "-v"
            action = :store_true
            help = "Enable verbose logging"
    end

    # Options for create subcommand
    @add_arg_table! s["create"] begin
        "package_name"
            help = "Name of the package to create"
            required = true
        "--author"
            help = "Package author name"
        "--user"
            help = "GitHub username"
        "--mail"
            help = "Email address attached to each author when generating the package"
        "--output-dir", "-o"
            help = "Output directory for the package"
            default = pwd()
        "--dry-run"
            action = :store_true
            help = "Show what would be done without executing"
    end

    # Mutually exclusive mise options
    add_arg_group!(s["create"], "mise options", exclusive=true)
    @add_arg_table! s["create"] begin
        "--with-mise"
            action = :store_true
            help = "Generate mise configuration file"
        "--no-mise"
            action = :store_true
            help = "Disable mise configuration file generation"
    end

    # Reset to default group for plugin options added later
    set_default_arg_group!(s["create"])

    # Options for config subcommand
    @add_arg_table! s["config"] begin
        "show"
            action = :command
            help = "Show current configuration"
        "set"
            action = :command
            help = "Set configuration values"
    end

    # Options for `config show`
    @add_arg_table! s["config"]["show"] begin
        "--config-file"
            help = "Path to custom configuration file"
    end

    # Options for `config set` — mirrors the porting source (JuliaPkgTemplatesCLI)
    @add_arg_table! s["config"]["set"] begin
        "--author"
            action = :append_arg
            help = "Set default author(s); repeat or use comma-separated values"
        "--user"
            help = "Set default Git hosting username"
        "--mail"
            help = "Set default email address"
        "--license"
            help = "Set default license name (e.g., MIT, Apache)"
        "--julia-version"
            help = "Set default Julia version constraint (e.g., 1.10.9)"
        "--mise-filename-base"
            help = "Set default base name for mise config file"
        "--config-file"
            help = "Path to custom configuration file"
    end

    # Mutually exclusive mise toggle for `config set`
    add_arg_group!(s["config"]["set"], "mise options", exclusive=true)
    @add_arg_table! s["config"]["set"] begin
        "--with-mise"
            action = :store_true
            help = "Set default to enable mise config generation"
        "--no-mise"
            action = :store_true
            help = "Set default to disable mise config generation"
    end

    # Reset to default group so dynamic plugin options land in the main group
    set_default_arg_group!(s["config"]["set"])

    # Options for plugin-info subcommand
    @add_arg_table! s["plugin-info"] begin
        "plugin_name"
            help = "Name of the plugin to show details"
            required = false
    end

    # Options for completion subcommand
    @add_arg_table! s["completion"] begin
        "shell"
            help = "Shell type (fish, bash, zsh)"
            required = true
    end

    return s
end

"""
Add dynamic plugin options (retrieved from PkgTemplates.jl at runtime)

# Arguments
- `settings::ArgParseSettings`: ArgParse settings object

# Side Effects
- Adds plugin options to the `settings["create"]` and `settings["config"]["set"]` subcommands

# Implementation Details
- Retrieves all plugin types via `PluginDiscovery.get_plugins()`
- Flag options (argumentless plugins) use `--srcdir` format
- Key-value options (plugins with arguments) use `--formatter style=blue` format
- License is skipped because `--license` is registered as an explicit value option
"""
function add_dynamic_plugin_options!(settings::ArgParseSettings)::Nothing
    # `create` keeps the historical flag-only behaviour for argumentless plugins.
    add_dynamic_plugin_options!(settings["create"]; skip_license=false,
                                 argumentless_as_flag=true)
    # `config set` accepts an optional KEY=VALUE bundle so users can persist
    # plugin-specific defaults (matches the Python port's `--git "ignore=..."` form).
    add_dynamic_plugin_options!(settings["config"]["set"]; skip_license=true,
                                 argumentless_as_flag=false)
    return nothing
end

# Internal helper: add plugin options to a specific subcommand settings node.
# `skip_license` avoids colliding with a separately-defined `--license` value option.
# `argumentless_as_flag=true` matches the legacy `create` registration where
# zero-arg plugins become bare flags. When false, every plugin accepts an
# optional space-separated KEY=VALUE string (`--plugin` / `--plugin "k=v ..."`).
function add_dynamic_plugin_options!(target;
                                      skip_license::Bool=false,
                                      argumentless_as_flag::Bool=true)::Nothing
    plugins = PluginDiscovery.get_plugins()

    for plugin in plugins
        plugin_name = string(nameof(plugin))
        if skip_license && plugin_name == "License"
            continue
        end
        option_name = "--$(lowercase(plugin_name))"
        is_argless = PluginDiscovery.is_argumentless_plugin(plugin)

        if argumentless_as_flag
            # `create` mode: keep the legacy registration shape so
            # `CreateCommand.parse_plugin_options` (which expects Vector
            # values for plugin keys) keeps working for any future
            # non-argumentless plugin.
            if is_argless
                ArgParse.add_arg_table!(target,
                    [option_name],
                    Dict(
                        :action => :store_true,
                        :help => "Enable $plugin_name plugin"
                    ))
            else
                ArgParse.add_arg_table!(target,
                    [option_name],
                    Dict(
                        :action => :append_arg,
                        :nargs => '*',
                        :metavar => "KEY=VALUE",
                        :help => "Options for $plugin_name plugin"
                    ))
            end
        else
            # `config set` mode: every plugin accepts an optional KEY=VALUE
            # bundle (`--plugin` enables defaults; `--plugin "k=v ..."`
            # supplies options), matching the Python port.
            ArgParse.add_arg_table!(target,
                [option_name],
                Dict(
                    :nargs => '?',
                    :constant => "",
                    :default => nothing,
                    :metavar => "KEY=VALUE",
                    :help => "Set $plugin_name plugin defaults (omit value to enable with defaults)"
                ))
        end
    end

    return nothing
end

"""
Get version information from Project.toml

# Returns
- `String`: Version string (e.g., "0.0.1")
"""
function get_version()::String
    project_file = joinpath(@__DIR__, "..", "Project.toml")
    project = TOML.parsefile(project_file)
    return get(project, "version", "unknown")
end

"""
Command dispatch function - routes parsed arguments to appropriate command handlers

# Arguments
- `command::String`: The subcommand to execute (create, config, plugin-info, completion)
- `args::Dict`: Parsed arguments specific to the subcommand

# Returns
- `CommandResult`: Result of command execution

# Throws
- `ErrorException`: If an unknown command is provided
"""
function dispatch_command(command::String, args::Dict)::CommandResult
    if command == "create"
        return CreateCommand.execute(args)
    elseif command == "config"
        return ConfigCommand.execute(args)
    elseif command == "plugin-info"
        return PluginInfoCommand.execute(args)
    elseif command == "completion"
        return CompletionCommand.execute(args)
    else
        error("Unknown command: $command")
    end
end

"""
Error handler - converts exceptions to user-friendly CommandResult

# Arguments
- `e::Exception`: The exception to handle

# Returns
- `CommandResult`: Error result with user-friendly message
"""
function handle_error(e::Exception)::CommandResult
    if e isa JTCError
        return CommandResult(
            success = false,
            message = string(e.message)
        )
    else
        return CommandResult(
            success = false,
            message = "Unexpected error: $(sprint(showerror, e))"
        )
    end
end

# Main entry point for the jtc CLI application (Julia 1.12 Apps feature)
#
# Returns:
# - Int: Exit code (0 for success, 1 for failure)
#
# Implementation Details:
# - Configures ArgParse.jl settings and adds dynamic plugin options
# - Parses command line arguments from ARGS
# - Configures logging based on --verbose flag
# - Dispatches to appropriate command handler
# - Catches and handles all exceptions, converting to user-friendly messages
function (@main)(ARGS)
    try
        # Create argument parser
        settings = create_argument_parser()

        # Add dynamic plugin options
        add_dynamic_plugin_options!(settings)

        # Parse arguments
        parsed_args = ArgParse.parse_args(ARGS, settings)

        # Configure logging based on verbose flag
        if get(parsed_args, "verbose", false)
            # Enable verbose logging (INFO and DEBUG messages)
            Logging.global_logger(Logging.ConsoleLogger(stderr, Logging.Debug))
        end

        # Get the subcommand
        command = get(parsed_args, "%COMMAND%", nothing)

        if command === nothing
            # No command specified, show help
            ArgParse.show_help(settings)
            return 0
        end

        # Dispatch to appropriate command handler
        result = dispatch_command(command, parsed_args[command])

        # Display result message if present
        if result.message !== nothing
            if result.success
                Logging.@info result.message
            else
                Logging.@error result.message
            end
        end

        return result.success ? 0 : 1

    catch e
        # Global error handler - catch any unhandled exceptions
        result = handle_error(e)
        Logging.@error result.message
        return 1
    end
end
