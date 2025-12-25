module JuliaPkgTemplatesCommandLineInterface

# Export error types
export JTCError
export JuliaDependencyError
export PackageGenerationError
export ConfigurationError
export TemplateGenerationError
export PluginNotFoundError

# Include error type definitions
include("errors.jl")

end
