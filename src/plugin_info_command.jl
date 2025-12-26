"""
PluginInfoCommand module for displaying PkgTemplates.jl plugin information.

Handles 'plugin-info' command execution, plugin list display,
and detailed plugin metadata formatting.
"""
module PluginInfoCommand

using PkgTemplates

# Import from parent module
using ..JuliaPkgTemplatesCommandLineInterface: CommandResult, PluginNotFoundError, PluginDetails
import ..PluginDiscovery

"""
    list_all_plugins(plugins::Vector{Type{<:PkgTemplates.Plugin}})::Nothing

Display list of all available PkgTemplates.jl plugins.

Prints a formatted list of plugin names to stdout.

# Arguments
- `plugins::Vector{Type{<:PkgTemplates.Plugin}}`: List of plugin types to display

# Example
```julia
plugins = PluginDiscovery.get_plugins()
PluginInfoCommand.list_all_plugins(plugins)
```
"""
function list_all_plugins(plugins::Vector{Type{<:PkgTemplates.Plugin}})::Nothing
    if isempty(plugins)
        println("No plugins available.")
        return nothing
    end

    println("Available PkgTemplates.jl plugins:")
    println()

    for PluginType in plugins
        plugin_name = String(nameof(PluginType))
        println("  - $plugin_name")
    end

    println()
    println("Total: $(length(plugins)) plugins")

    return nothing
end

"""
    show_plugin_details(details::PluginDetails)::Nothing

Display detailed information about a specific plugin.

Prints plugin name, fields, types, and default values to stdout.

# Arguments
- `details::PluginDetails`: Plugin metadata to display

# Example
```julia
details = PluginDiscovery.get_plugin_details("Git")
PluginInfoCommand.show_plugin_details(details)
```
"""
function show_plugin_details(details::PluginDetails)::Nothing
    println("Plugin: $(details.name)")
    println()

    if isempty(details.fields)
        println("This plugin has no configurable fields.")
        return nothing
    end

    println("Fields:")
    for (i, field) in enumerate(details.fields)
        field_type = details.types[i]
        default_val = details.defaults[i]

        println("  - $field :: $field_type")
        println("    Default: $default_val")
    end

    return nothing
end

"""
    execute(args::Dict{String, Any})::CommandResult

Execute 'plugin-info' command.

Displays either a list of all plugins (when no plugin name is specified)
or detailed information about a specific plugin.

# Arguments
- `args::Dict{String, Any}`: Parsed command-line arguments
  - `"plugin_name"`: (Optional) Name of plugin to show details for

# Returns
- `CommandResult`: Result of command execution

# Examples
```julia
# List all plugins
result = PluginInfoCommand.execute(Dict{String,Any}())

# Show details for specific plugin
result = PluginInfoCommand.execute(Dict{String,Any}("plugin_name" => "Git"))
```
"""
function execute(args::Dict{String,Any})::CommandResult
    try
        plugin_name = get(args, "plugin_name", nothing)

        if plugin_name === nothing
            # List all plugins
            plugins = PluginDiscovery.get_plugins()
            list_all_plugins(plugins)
            return CommandResult(success=true)
        else
            # Show specific plugin details
            details = PluginDiscovery.get_plugin_details(String(plugin_name))
            show_plugin_details(details)
            return CommandResult(success=true)
        end

    catch e
        # Handle PluginNotFoundError specifically
        if e isa PluginNotFoundError
            return CommandResult(
                success=false,
                message="Plugin '$(e.plugin_name)' not found. Available plugins: $(join(e.available_plugins, ", "))"
            )
        else
            # Handle other errors gracefully
            return CommandResult(
                success=false,
                message="Error executing plugin-info command: $(sprint(showerror, e))"
            )
        end
    end
end

end  # module PluginInfoCommand
