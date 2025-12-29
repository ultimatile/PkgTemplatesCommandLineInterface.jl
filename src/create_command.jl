"""
CreateCommand module

Implements the `create` command execution logic, including:
- Configuration file and CLI argument merging
- Plugin option parsing
- Dry-run mode handling
- Package generation orchestration
"""
module CreateCommand

using ..JuliaPkgTemplatesCommandLineInterface: CommandResult, PackageGenerationError
import ..ConfigManager
import ..PackageGenerator
import ..TemplateManager

export execute, merge_config, parse_plugin_options, parse_plugin_option_value

"""
    merge_config(config_defaults::Dict, cli_args::Dict)::Dict

Merge configuration file defaults with CLI arguments.
CLI arguments take precedence over config defaults.
Nothing values in CLI args are ignored (config values preserved).
Nested dictionaries are merged recursively.
"""
function merge_config(config_defaults::Dict, cli_args::Dict)::Dict
    merged = copy(config_defaults)

    for (key, value) in cli_args
        if haskey(merged, key) && value isa Dict && merged[key] isa Dict
            # Nested configuration merge
            merged[key] = merge(merged[key], value)
        elseif value !== nothing
            # CLI argument overrides config (only if not nothing)
            merged[key] = value
        end
    end

    return merged
end

"""
    parse_plugin_option_value(opt::String)::Tuple{String, Any}

Parse plugin option from "key=value" string format.
Performs type inference:
- "true" / "false" → Bool
- "123" → Int
- "1.5" → Float64
- "[a,b,c]" → Vector{String}
- Otherwise → String
"""
function parse_plugin_option_value(opt::String)::Tuple{String, Any}
    parts = split(opt, '=', limit=2)
    if length(parts) != 2
        error("Invalid plugin option format: '$opt'. Expected 'key=value'")
    end

    key, value_str = parts[1], parts[2]

    value = if value_str == "true"
        true
    elseif value_str == "false"
        false
    elseif startswith(value_str, "[") && endswith(value_str, "]")
        # Array parsing: "[item1,item2]" → ["item1", "item2"]
        inner = value_str[2:end-1]  # Remove brackets
        if isempty(inner)
            String[]
        else
            split(inner, ',')
        end
    elseif occursin(r"^\d+$", value_str)
        parse(Int, value_str)
    elseif occursin(r"^\d+\.\d+$", value_str)
        parse(Float64, value_str)
    else
        value_str  # String as-is
    end

    return (String(key), value)
end

"""
    parse_plugin_options(args::Dict)::Dict{String, Dict{String, Any}}

Parse plugin options from CLI arguments.
Extracts all "--plugin-name" keys with Vector values,
converts "key=value" strings to typed Dict entries.
"""
function parse_plugin_options(args::Dict)::Dict{String, Dict{String, Any}}
    plugin_options = Dict{String, Dict{String, Any}}()

    for (key, values) in args
        # Plugin option keys start with "--" and have Vector values
        if startswith(String(key), "--") && values isa Vector
            plugin_name = replace(String(key), "--" => "", count=1)
            plugin_options[plugin_name] = Dict{String, Any}()

            for opt_str in values
                opt_key, opt_value = parse_plugin_option_value(opt_str)
                plugin_options[plugin_name][opt_key] = opt_value
            end
        end
    end

    return plugin_options
end

"""
    execute(args::Dict{String, Any})::CommandResult

Execute the create command.

# Arguments
- `args`: Parsed CLI arguments (from ArgParse.jl)

# Returns
- `CommandResult` with success status and message

# Behavior
1. Load config file and merge with CLI args (CLI takes precedence)
2. Parse plugin options from CLI
3. If --dry-run, show execution plan without side effects
4. Create package using PackageGenerator
5. Optionally generate mise config (if --with-mise is true)
"""
function execute(args::Dict{String, Any})::CommandResult
    try
        # Load and merge configuration
        config = ConfigManager.load_config()
        config_defaults = get(config, "default", Dict{String, Any}())
        merged_options = merge_config(config_defaults, args)

        # Parse plugin options from CLI
        plugin_options = parse_plugin_options(args)

        # Extract plugin options from config (nested Dicts with capitalized keys)
        for (key, value) in merged_options
            if value isa Dict && !isempty(key) && isuppercase(first(key))
                # Merge with CLI plugin options (CLI takes precedence)
                if haskey(plugin_options, key)
                    plugin_options[key] = merge(Dict{String,Any}(k => v for (k,v) in value), plugin_options[key])
                else
                    plugin_options[key] = Dict{String,Any}(k => v for (k,v) in value)
                end
            end
        end

        # Dry-run check
        if get(args, "dry-run", false)
            return show_dry_run_plan(merged_options, plugin_options, args)
        end

        # Validate package name
        package_name = get(args, "package_name", nothing)
        if package_name === nothing
            return CommandResult(
                success=false,
                message="Package name is required"
            )
        end

        # Transform author (singular) to authors (plural array) for PkgTemplates.jl
        if haskey(merged_options, "author") && !haskey(merged_options, "authors")
            author = merged_options["author"]
            merged_options["authors"] = author == "" ? String[] : [author]
        end

        # Create package
        output_dir = get(merged_options, "output-dir", pwd())
        PackageGenerator.create_package(package_name, merged_options, plugin_options, output_dir)

        # Generate mise config if requested
        if get(merged_options, "with_mise", true)
            try
                TemplateManager.generate_mise_config(package_name, merged_options)
            catch e
                @warn "Failed to generate mise config" exception=e
            end
        end

        return CommandResult(
            success=true,
            message="Package $package_name created successfully"
        )
    catch e
        return handle_error(e)
    end
end

"""
    show_dry_run_plan(merged_options::Dict, plugin_options::Dict, args::Dict)::CommandResult

Display execution plan without performing actual operations.
"""
function show_dry_run_plan(
    merged_options::Dict,
    plugin_options::Dict,
    args::Dict
)::CommandResult
    package_name = get(args, "package_name", "UnknownPackage")

    println("Dry-run mode: showing execution plan without creating files")
    println()
    println("Package name: $package_name")
    println()
    println("Merged options:")
    for (key, value) in merged_options
        println("  $key = $value")
    end
    println()
    println("Plugin options:")
    for (plugin, options) in plugin_options
        println("  Plugin: $plugin")
        for (key, value) in options
            println("    $key = $value")
        end
    end

    return CommandResult(success=true, message="Dry-run completed")
end

"""
    handle_error(e::Exception)::CommandResult

Convert exceptions to user-friendly CommandResult.
"""
function handle_error(e::Exception)::CommandResult
    if e isa PackageGenerationError
        return CommandResult(
            success=false,
            message="Package generation failed: $(e.message)"
        )
    else
        return CommandResult(
            success=false,
            message="Error: $(sprint(showerror, e))"
        )
    end
end

end  # module CreateCommand
