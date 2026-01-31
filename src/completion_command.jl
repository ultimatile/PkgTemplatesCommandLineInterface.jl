"""
CompletionCommand module for generating shell completion scripts.

Handles 'completion' command execution, shell completion script generation,
and dynamic plugin integration.
"""
module CompletionCommand

using PkgTemplates
using ..JuliaPkgTemplatesCommandLineInterface: CommandResult, TemplateGenerationError, PluginDiscovery, TemplateManager

"""
    execute(args::Dict{String, Any})::CommandResult

Execute 'completion' command.

Generates shell completion scripts for the specified shell.
Currently only fish shell is supported.

# Arguments
- `args::Dict{String, Any}`: Parsed command-line arguments
  - `"shell"`: (Optional) Shell type (defaults to "fish")

# Returns
- `CommandResult`: Result of command execution

# Examples
```julia
# Generate fish completion (default)
result = CompletionCommand.execute(Dict{String,Any}())

# Generate fish completion (explicit)
result = CompletionCommand.execute(Dict{String,Any}("shell" => "fish"))

# Attempt unsupported shell
result = CompletionCommand.execute(Dict{String,Any}("shell" => "bash"))
# Returns: CommandResult(success=false, message="Only fish shell is supported currently")
```
"""
function execute(args::Dict{String,Any})::CommandResult
    try
        # Get shell type, default to fish
        shell = get(args, "shell", "fish")

        # Check if shell is supported
        if shell ∉ ("fish", "bash", "zsh")
            return CommandResult(
                success=false,
                message="Unsupported shell: $shell. Supported: fish, bash, zsh"
            )
        end

        # Get plugin list for dynamic completion
        plugins = PluginDiscovery.get_plugins()
        plugin_names = String[String(nameof(p)) for p in plugins]

        # Generate completion script
        completion_script = TemplateManager.generate_completion(shell, plugin_names)

        # Print completion script to stdout
        println(completion_script)

        return CommandResult(success=true)

    catch e
        # Handle template generation errors
        if e isa TemplateGenerationError
            return CommandResult(
                success=false,
                message="Failed to generate completion script: $(e.message)"
            )
        else
            # Handle other unexpected errors gracefully
            return CommandResult(
                success=false,
                message="Error executing completion command: $(sprint(showerror, e))"
            )
        end
    end
end

end  # module CompletionCommand
