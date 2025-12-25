module JuliaPkgTemplatesCommandLineInterface

# Export error types
export JTCError
export JuliaDependencyError
export PackageGenerationError
export ConfigurationError
export TemplateGenerationError
export PluginNotFoundError

# Export common data structures
export CommandResult
export PluginDetails

# Include error type definitions
include("errors.jl")

# Include common data structures
include("types.jl")

# Include ConfigManager module
include("config_manager.jl")

# Include PluginDiscovery module
include("plugin_discovery.jl")

end
