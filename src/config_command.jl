"""
ConfigCommand module for managing CLI configuration commands.

Handles 'config show' and 'config set' subcommands for configuration management.
"""
module ConfigCommand

using TOML

# Import from parent module
using ..JuliaPkgTemplatesCommandLineInterface: CommandResult, JTCError, ConfigurationError
import ..ConfigManager

"""
    format_config(config::Dict{String, Any})::String

Format configuration dictionary as TOML string for display.

# Arguments
- `config::Dict{String, Any}`: Configuration dictionary to format

# Returns
- `String`: TOML-formatted string representation of the configuration

# Example
```julia
config = Dict("default" => Dict("author" => "John Doe"))
formatted = ConfigCommand.format_config(config)
println(formatted)
# Output:
# [default]
# author = "John Doe"
```
"""
function format_config(config::Dict{String,Any})::String
    io = IOBuffer()
    TOML.print(io, config)
    return String(take!(io))
end

"""
    update_config(existing_config::Dict, new_values::Dict)::Dict

Merge new configuration values with existing configuration.

Preserves existing values that are not being updated. Supports nested
configuration using dot notation (e.g., "formatter.style").

# Arguments
- `existing_config::Dict`: Current configuration dictionary
- `new_values::Dict`: New values to merge (key-value pairs or dot notation)

# Returns
- `Dict`: Updated configuration with new values merged in

# Priority
New values override existing values for the same key.

# Special Handling
- Ignores command-related keys: "show", "set", "%SUBCOMMAND%"
- Supports dot notation: "formatter.style" creates nested structure
- Creates nested sections if they don't exist

# Example
```julia
existing = Dict("default" => Dict("author" => "Old"))
new = Dict("author" => "New", "formatter.style" => "blue")
updated = ConfigCommand.update_config(existing, new)
# Result: Dict("default" => Dict("author" => "New", "formatter" => Dict("style" => "blue")))
```
"""
function update_config(existing_config::Dict, new_values::Dict)::Dict
    updated = deepcopy(existing_config)

    # Ensure "default" section exists
    if !haskey(updated, "default")
        updated["default"] = Dict{String,Any}()
    end

    for (key, value) in new_values
        # Skip command-related keys
        if key in ["show", "set", "%SUBCOMMAND%"]
            continue
        end

        # Handle nested configuration with dot notation
        if contains(key, '.')
            parts = split(key, '.', limit=2)
            section, option = parts[1], parts[2]

            # Create section if it doesn't exist
            if !haskey(updated["default"], section)
                updated["default"][section] = Dict{String,Any}()
            end

            # Convert to Dict if needed
            if !(updated["default"][section] isa Dict)
                updated["default"][section] = Dict{String,Any}()
            end

            updated["default"][section][option] = value
        else
            # Simple key-value update
            updated["default"][key] = value
        end
    end

    return updated
end

"""
    execute(args::Dict{String, Any})::CommandResult

Execute 'config' command with show/set subcommands.

# Arguments
- `args::Dict{String, Any}`: Parsed command-line arguments
  - "%SUBCOMMAND%": Subcommand to execute ("show" or "set"), defaults to "show"
  - Other keys: Configuration values for "set" subcommand

# Returns
- `CommandResult`: Result of command execution

# Subcommands
- `show`: Display current configuration in TOML format
- `set`: Update configuration with new values

# Examples
```julia
# Show current configuration
result = ConfigCommand.execute(Dict("%SUBCOMMAND%" => "show"))

# Set configuration values
result = ConfigCommand.execute(Dict(
    "%SUBCOMMAND%" => "set",
    "author" => "Jane Doe",
    "formatter.style" => "blue"
))
```
"""
function execute(args::Dict{String,Any})::CommandResult
    try
        # Default to "show" if no subcommand specified
        subcommand = get(args, "%SUBCOMMAND%", "show")

        if subcommand == "show"
            # Load and display configuration
            config = ConfigManager.load_config()
            formatted = format_config(config)
            println(formatted)
            return CommandResult(success=true)

        elseif subcommand == "set"
            # Load existing configuration
            config = ConfigManager.load_config()

            # Update with new values
            updated_config = update_config(config, args)

            # Save updated configuration
            ConfigManager.save_config(updated_config)

            return CommandResult(success=true, message="Configuration updated successfully")

        else
            # Unknown subcommand
            return CommandResult(
                success=false,
                message="Unknown config subcommand: $subcommand"
            )
        end

    catch e
        # Handle errors gracefully
        return CommandResult(
            success=false,
            message="Error executing config command: $(sprint(showerror, e))"
        )
    end
end

end  # module ConfigCommand
