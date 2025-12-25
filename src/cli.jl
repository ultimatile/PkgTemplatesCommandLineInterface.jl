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
        "--dry-run"
            action = :store_true
            help = "Show what would be done without executing"
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
        "--output-dir", "-o"
            help = "Output directory for the package"
            default = pwd()
        "--with-mise"
            action = :store_true
            help = "Generate mise configuration file"
    end

    # Options for config subcommand
    @add_arg_table! s["config"] begin
        "show"
            action = :command
            help = "Show current configuration"
        "set"
            action = :command
            help = "Set configuration values"
    end

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
- Adds plugin options to the `settings["create"]` subcommand

# Implementation Details
- Retrieves all plugin types via `PluginDiscovery.get_plugins()`
- Flag options (argumentless plugins) use `--srcdir` format
- Key-value options (plugins with arguments) use `--formatter style=blue` format
"""
function add_dynamic_plugin_options!(settings::ArgParseSettings)::Nothing
    plugins = PluginDiscovery.get_plugins()

    for plugin in plugins
        plugin_name = string(nameof(plugin))
        option_name = "--$(lowercase(plugin_name))"

        # Determine if this is a flag option (argumentless plugin)
        if PluginDiscovery.is_argumentless_plugin(plugin)
            ArgParse.add_arg_table!(settings["create"],
                [option_name],
                Dict(
                    :action => :store_true,
                    :help => "Enable $plugin_name plugin"
                ))
        else
            ArgParse.add_arg_table!(settings["create"],
                [option_name],
                Dict(
                    :action => :append_arg,
                    :nargs => '*',
                    :metavar => "KEY=VALUE",
                    :help => "Options for $plugin_name plugin"
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
