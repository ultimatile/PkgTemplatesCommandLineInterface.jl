"""
Custom error types for PkgTemplatesCommandLineInterface.

This module defines a hierarchy of error types used throughout the application
to provide clear, user-friendly error messages.
"""

"""
    JTCError <: Exception

Abstract base type for all JuliaPkgTemplatesCLI custom errors.

All custom error types in this application inherit from `JTCError`,
allowing for unified error handling across the codebase.
"""
abstract type JTCError <: Exception end

"""
    JuliaDependencyError <: JTCError

Error indicating Julia version or dependency issues.

# Fields
- `message::String`: Description of the dependency error

# Example
```julia
throw(JuliaDependencyError("Julia 1.12+ is required"))
```
"""
struct JuliaDependencyError <: JTCError
    message::String
end

Base.showerror(io::IO, e::JuliaDependencyError) = print(io, "JuliaDependencyError: ", e.message)

"""
    PackageGenerationError <: JTCError

Error occurring during package generation.

# Fields
- `message::String`: Description of the generation error
- `cause::Union{Exception, Nothing}`: Optional underlying exception that caused this error

# Example
```julia
throw(PackageGenerationError("Failed to generate package"))
# With cause
throw(PackageGenerationError("Failed to generate package"; cause=original_exception))
```
"""
struct PackageGenerationError <: JTCError
    message::String
    cause::Union{Exception,Nothing}

    PackageGenerationError(message::String; cause::Union{Exception,Nothing}=nothing) =
        new(message, cause)
end

function Base.showerror(io::IO, e::PackageGenerationError)
    print(io, "PackageGenerationError: ", e.message)
    if e.cause !== nothing
        print(io, "\nCaused by: ", e.cause)
    end
end

"""
    ConfigurationError <: JTCError

Error related to configuration file handling.

# Fields
- `message::String`: Description of the configuration error
- `config_path::String`: Path to the configuration file that caused the error

# Example
```julia
throw(ConfigurationError("Invalid TOML syntax", "/path/to/config.toml"))
```
"""
struct ConfigurationError <: JTCError
    message::String
    config_path::String
end

function Base.showerror(io::IO, e::ConfigurationError)
    print(io, "ConfigurationError: ", e.message)
    print(io, "\nConfiguration file: ", e.config_path)
end

"""
    TemplateGenerationError <: JTCError

Error occurring during template file generation.

# Fields
- `message::String`: Description of the template error
- `template_path::String`: Path to the template file that caused the error

# Example
```julia
throw(TemplateGenerationError("Template not found", "/path/to/template.mustache"))
```
"""
struct TemplateGenerationError <: JTCError
    message::String
    template_path::String
end

function Base.showerror(io::IO, e::TemplateGenerationError)
    print(io, "TemplateGenerationError: ", e.message)
    print(io, "\nTemplate file: ", e.template_path)
end

"""
    PluginNotFoundError <: JTCError

Error indicating a requested plugin was not found.

# Fields
- `plugin_name::String`: Name of the plugin that was not found
- `available_plugins::Vector{String}`: List of available plugin names

# Example
```julia
throw(PluginNotFoundError("NonExistent", ["Git", "Formatter", "License"]))
```
"""
struct PluginNotFoundError <: JTCError
    plugin_name::String
    available_plugins::Vector{String}
end

function Base.showerror(io::IO, e::PluginNotFoundError)
    print(io, "PluginNotFoundError: Plugin '", e.plugin_name, "' not found")
    if !isempty(e.available_plugins)
        print(io, "\nAvailable plugins: ", join(e.available_plugins, ", "))
    end
end

"""
    PluginOptionFormatError <: JTCError

Error indicating a plugin option was supplied in an unsupported form
(currently: comma-separated `KEY=VALUE` pairs, which clig.dev flags as
an anti-pattern because values may legitimately contain commas).

# Fields
- `message::String`: Description of the format violation, including the
  offending value and the canonical replacement forms.

# Example
```julia
throw(PluginOptionFormatError(
    "Plugin option value \"true,project=true\" looks like a comma-separated " *
    "list of KEY=VALUE pairs, which is not supported. Please use one of:\n" *
    "  --tests aqua=true --tests project=true\n" *
    "  --tests \"aqua=true project=true\""
))
```
"""
struct PluginOptionFormatError <: JTCError
    message::String
end

Base.showerror(io::IO, e::PluginOptionFormatError) =
    print(io, "PluginOptionFormatError: ", e.message)
