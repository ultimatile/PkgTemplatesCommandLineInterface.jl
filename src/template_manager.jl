"""
TemplateManager module for Mustache.jl template generation.

This module provides functionality for generating mise configuration files
and shell completion scripts using Mustache.jl templates.
"""

module TemplateManager

using Mustache
using ..JuliaPkgTemplatesCommandLineInterface: TemplateGenerationError

"""
    generate_mise_config(package_name::String, options::Dict{String, Any})::Nothing

Generate a mise configuration file for the given package.

Uses Mustache.jl to render the mise.toml template with package-specific data.

# Arguments
- `package_name::String`: Name of the package for which to generate mise config
- `options::Dict{String, Any}`: Configuration options including `mise_filename_base`

# Throws
- `TemplateGenerationError`: If template file is missing or rendering fails

# Example
```julia
options = Dict("mise_filename_base" => ".mise")
TemplateManager.generate_mise_config("MyPackage", options)
```
"""
function generate_mise_config(
    package_name::String,
    options::Dict{String,Any}
)::Nothing
    template_path = joinpath(@__DIR__, "templates", "mise.toml.mustache")

    try
        # Read template file
        if !isfile(template_path)
            throw(TemplateGenerationError(
                "Template file not found",
                template_path
            ))
        end

        template = read(template_path, String)

        # Prepare template data
        data = Dict(
            "package_name" => package_name,
            "project_dir" => "@",
            "mise_filename_base" => get(options, "mise_filename_base", ".mise")
        )

        # Render template
        rendered = Mustache.render(template, data)

        # Write output file
        output_path = joinpath(package_name, "$(data["mise_filename_base"]).toml")
        write(output_path, rendered)

        # Log success (would use @info in production with logging configured)
        # @info "Generated mise configuration at $output_path"
    catch e
        if e isa TemplateGenerationError
            rethrow(e)
        else
            throw(TemplateGenerationError(
                "Failed to generate mise config: $(sprint(showerror, e))",
                template_path
            ))
        end
    end

    return nothing
end

"""
    generate_completion(shell::String, plugin_names::Vector{String})::String

Generate shell completion script for the given shell.

Currently supports fish shell only.

# Arguments
- `shell::String`: Shell type (currently only "fish" is supported)
- `plugin_names::Vector{String}`: List of plugin names to include in completions

# Returns
- `String`: Rendered completion script

# Throws
- `TemplateGenerationError`: If template file is missing or rendering fails

# Example
```julia
plugins = ["Git", "Formatter", "License"]
completion = TemplateManager.generate_completion("fish", plugins)
```
"""
function generate_completion(
    shell::String,
    plugin_names::Vector{String}
)::String
    template_path = joinpath(@__DIR__, "templates", "$(shell)_completion.mustache")

    try
        # Read template file
        if !isfile(template_path)
            throw(TemplateGenerationError(
                "Template file not found for shell: $shell",
                template_path
            ))
        end

        template = read(template_path, String)

        # Prepare template data
        # Mustache.jl expects an array of dictionaries for iteration
        data = Dict(
            "plugins" => [Dict("name" => name) for name in plugin_names]
        )

        # Render template
        rendered = Mustache.render(template, data)

        return rendered
    catch e
        if e isa TemplateGenerationError
            rethrow(e)
        else
            throw(TemplateGenerationError(
                "Failed to generate $shell completion: $(sprint(showerror, e))",
                template_path
            ))
        end
    end
end

end # module TemplateManager
