"""
PackageGenerator module for JuliaPkgTemplatesCommandLineInterface.

This module provides functionality to generate Julia packages using PkgTemplates.jl,
including plugin instantiation and error handling.
"""

module PackageGenerator

using PkgTemplates
using ..JuliaPkgTemplatesCommandLineInterface: PackageGenerationError

export create_package, instantiate_plugins

"""
    create_package(name::String, options::Dict{String,Any}, plugin_options::Dict{String,Dict{String,Any}}, output_dir::String=pwd())

Generate a Julia package using PkgTemplates.jl with the specified options and plugins.

# Arguments
- `name::String`: Name of the package to create
- `options::Dict{String,Any}`: General package options (user, authors, julia_version, etc.)
- `plugin_options::Dict{String,Dict{String,Any}}`: Plugin-specific options
- `output_dir::String`: Directory where the package will be created (defaults to current directory)

# Throws
- `PackageGenerationError`: If package generation fails

# Examples
```julia
options = Dict{String,Any}(
    "user" => "myuser",
    "authors" => ["My Name <email@example.com>"]
)
plugin_options = Dict{String,Dict{String,Any}}(
    "Git" => Dict{String,Any}("manifest" => true)
)
create_package("MyPackage", options, plugin_options)
```
"""
function create_package(
    name::String,
    options::Dict{String,Any},
    plugin_options::Dict{String,Dict{String,Any}},
    output_dir::String=pwd()
)::Nothing
    try
        # Instantiate plugins with their options
        plugins = instantiate_plugins(plugin_options)

        # Build Template object with provided options
        template = PkgTemplates.Template(;
            user=get(options, "user", ""),
            authors=get(options, "authors", String[]),
            julia=VersionNumber(get(options, "julia_version", "1.10")),
            plugins=plugins,
            dir=output_dir
        )

        # Generate the package using the modern callable interface
        template(name)
    catch e
        # Convert PkgTemplates and other errors to PackageGenerationError
        if e isa ArgumentError
            throw(PackageGenerationError("Invalid package configuration: $(e.msg)"; cause=e))
        else
            # Re-wrap all other exceptions
            throw(PackageGenerationError("Failed to generate package: $(sprint(showerror, e))"; cause=e))
        end
    end

    return nothing
end

"""
    instantiate_plugins(plugin_options::Dict{String,Dict{String,Any}})::Vector{PkgTemplates.Plugin}

Instantiate PkgTemplates.jl plugins from plugin options.

# Arguments
- `plugin_options::Dict{String,Dict{String,Any}}`: Dictionary mapping plugin names to their options

# Returns
- `Vector{PkgTemplates.Plugin}`: Vector of instantiated plugin objects

# Throws
- `Exception`: If plugin type doesn't exist or instantiation fails

# Examples
```julia
plugin_options = Dict{String,Dict{String,Any}}(
    "Git" => Dict{String,Any}("manifest" => true, "ssh" => false),
    "Readme" => Dict{String,Any}()
)
plugins = instantiate_plugins(plugin_options)
```
"""
function instantiate_plugins(plugin_options::Dict{String,Dict{String,Any}})::Vector{PkgTemplates.Plugin}
    plugins = PkgTemplates.Plugin[]

    for (plugin_name, options) in plugin_options
        # Get the plugin type from PkgTemplates module
        PluginType = getfield(PkgTemplates, Symbol(plugin_name))

        # Convert types as needed
        processed_options = Dict{String,Any}()
        for (k, v) in options
            if k == "ignore" && v isa String
                processed_options[k] = split(v, ',')
            elseif k == "version" && v isa String
                processed_options[k] = VersionNumber(v)
            else
                processed_options[k] = v
            end
        end

        # Instantiate plugin with options
        plugin_instance = if isempty(processed_options)
            PluginType()
        else
            kwargs = (Symbol(k) => v for (k, v) in processed_options)
            PluginType(; kwargs...)
        end

        push!(plugins, plugin_instance)
    end

    return plugins
end

end  # module PackageGenerator
