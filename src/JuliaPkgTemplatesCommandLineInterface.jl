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

# Include TemplateManager module
include("template_manager.jl")

# Include PackageGenerator module
include("package_generator.jl")

# Include CreateCommand module
include("create_command.jl")

# Include ConfigCommand module
include("config_command.jl")

# Include PluginInfoCommand module
include("plugin_info_command.jl")

# Include CompletionCommand module
include("completion_command.jl")

# Include CLI module
include("cli.jl")

# Export CLI functions
export create_argument_parser
export add_dynamic_plugin_options!
export get_version

end
