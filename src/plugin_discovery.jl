"""
PluginDiscovery module for PkgTemplates.jl plugin dynamic discovery.

Provides functions for discovering available plugins, extracting metadata,
and detecting zero-argument plugins.
"""
module PluginDiscovery

using PkgTemplates
using JuliaPkgTemplatesCommandLineInterface: PluginDetails, PluginNotFoundError

"""
    get_plugins()::Vector{Type{<:PkgTemplates.Plugin}}

Get all concrete plugin types from PkgTemplates.jl.

Uses the official `PkgTemplates.concretes()` API to recursively discover
all concrete plugin types, sorted alphabetically by name.

# Returns
- `Vector{Type{<:PkgTemplates.Plugin}}`: Sorted list of all plugin types

# Example
```julia
plugins = PluginDiscovery.get_plugins()
# Returns: [AppVeyor, BlueStyleBadge, CirrusCI, ...]
```
"""
function get_plugins()::Vector{Type{<:PkgTemplates.Plugin}}
    return PkgTemplates.concretes(PkgTemplates.Plugin)
end

"""
    is_argumentless_plugin(PluginType::Type{<:PkgTemplates.Plugin})::Bool

Check if a plugin has a zero-argument constructor.

Attempts to instantiate the plugin with zero arguments. Returns `true` if
successful, `false` if a `MethodError` is raised.

# Arguments
- `PluginType::Type{<:PkgTemplates.Plugin}`: Plugin type to check

# Returns
- `Bool`: `true` if plugin can be instantiated with zero arguments

# Example
```julia
PluginDiscovery.is_argumentless_plugin(PkgTemplates.Readme)
# Returns: true

PluginDiscovery.is_argumentless_plugin(PkgTemplates.Git)
# Returns: true (all PkgTemplates.jl plugins have zero-arg constructors)
```
"""
function is_argumentless_plugin(PluginType::Type{<:PkgTemplates.Plugin})::Bool
    try
        # Attempt to instantiate with zero arguments
        PluginType()
        return true
    catch e
        if e isa MethodError
            return false
        else
            # Re-throw unexpected errors
            rethrow(e)
        end
    end
end

"""
    get_plugin_details(plugin_name::String)::PluginDetails

Get detailed metadata for a specific plugin.

Extracts field names, types, and default values using PkgTemplates.jl's
reflection API (`fieldnames`, `fieldtype`, `defaultkw`).

# Arguments
- `plugin_name::String`: Name of the plugin (e.g., "Git", "License")

# Returns
- `PluginDetails`: Metadata including name, fields, types, and defaults

# Throws
- `PluginNotFoundError`: If plugin name doesn't exist

# Example
```julia
details = PluginDiscovery.get_plugin_details("Git")
# Returns: PluginDetails with Git plugin metadata
```
"""
function get_plugin_details(plugin_name::String)::PluginDetails
    # Try to get the plugin type
    PluginType = try
        getfield(PkgTemplates, Symbol(plugin_name))
    catch e
        if e isa UndefVarError
            # Plugin not found, provide helpful error
            available_plugins = String[String(nameof(p)) for p in get_plugins()]
            throw(PluginNotFoundError(plugin_name, available_plugins))
        else
            rethrow(e)
        end
    end

    # Verify it's actually a Plugin subtype
    if !(PluginType <: PkgTemplates.Plugin)
        available_plugins = String[String(nameof(p)) for p in get_plugins()]
        throw(PluginNotFoundError(plugin_name, available_plugins))
    end

    # Extract field information
    field_names = fieldnames(PluginType)
    fields = Symbol[f for f in field_names]  # Ensure Vector{Symbol}
    field_types = Type[fieldtype(PluginType, f) for f in fields]

    # Extract default values using PkgTemplates.defaultkw
    default_values = Any[]
    for f in fields
        default_val = try
            # Try using PkgTemplates.defaultkw (official API for @plugin macro)
            PkgTemplates.defaultkw(PluginType, Val(f))
        catch
            # Fallback: try instantiating with zero arguments
            if is_argumentless_plugin(PluginType)
                instance = PluginType()
                getfield(instance, f)
            else
                # If all else fails, return nothing
                nothing
            end
        end
        push!(default_values, default_val)
    end

    return PluginDetails(
        name=plugin_name,
        fields=fields,
        types=field_types,
        defaults=default_values
    )
end

end  # module PluginDiscovery
