"""
CreateCommand module

Implements the `create` command execution logic, including:
- Configuration file and CLI argument merging
- Plugin option parsing
- Dry-run mode handling
- Package generation orchestration
"""
module CreateCommand

using ..PkgTemplatesCommandLineInterface: CommandResult, JTCError, PackageGenerationError
import ..ConfigManager
import ..PackageGenerator
import ..PluginDiscovery
import ..PluginOptionParser
import ..TemplateManager

export execute, merge_config, parse_plugin_options

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
    parse_plugin_options(args::Dict)::Dict{String, Dict{String, Any}}

Translate CLI plugin options from `args` into the
`Dict{Canonical => Dict{key => typed_value}}` shape that
`PackageGenerator.create_package` consumes.

ArgParse stores plugin option keys as the lowercase plugin name (no `--`
prefix). With the `:append_arg, nargs='?', constant="", default=nothing`
registration, the value is one of:
- `nothing`     → `--<plugin>` not supplied; skip.
- `String[]`    → `--<plugin>` not supplied (alternate ArgParse default
  for `:append_arg`); skip.
- `Vector`      → one element per `--<plugin>` invocation. Each element
  is `""` (bare flag → use defaults) or a `"k=v ..."` bundle. Elements
  are merged left-to-right with last-wins on duplicate keys, matching
  POSIX/GNU/clig.dev convention for repeat-flag aggregation.
- `String`      → legacy direct-call shape kept so tests / direct callers
  can still pass a single bundle. Equivalent to a 1-element vector.

Output keys are canonicalised against `PluginDiscovery.canonical_names()`
so PkgTemplates plugin types resolve via `getfield(PkgTemplates, Symbol(...))`.
"""
function parse_plugin_options(args::Dict)::Dict{String, Dict{String, Any}}
    plugin_options = Dict{String, Dict{String, Any}}()
    canonical = PluginDiscovery.canonical_names()

    for (lower_name, canonical_name) in canonical
        haskey(args, lower_name) || continue
        value = args[lower_name]
        flag = "--$lower_name"

        if value === nothing
            continue
        elseif value isa AbstractString
            section = isempty(value) ?
                Dict{String, Any}() :
                PluginOptionParser.parse_kv_string(value; plugin_flag=flag)
            plugin_options[canonical_name] = section
        elseif value isa AbstractVector
            isempty(value) && continue
            section = Dict{String, Any}()
            for elem in value
                elem isa AbstractString || continue
                isempty(elem) && continue
                merge!(section, PluginOptionParser.parse_kv_string(elem; plugin_flag=flag))
            end
            plugin_options[canonical_name] = section
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

        # Transform author (singular) to authors (plural array) for PkgTemplates.jl.
        # `config set --author A --author B` may persist author as Vector{String};
        # accept that shape too so the value flows into PkgTemplates unchanged.
        if haskey(merged_options, "author") && !haskey(merged_options, "authors")
            author = merged_options["author"]
            merged_options["authors"] = if author isa AbstractVector
                String[String(a) for a in author]
            elseif author == ""
                String[]
            else
                [author]
            end
        end

        # Attach `mail` to every author entry that doesn't already carry an
        # email so the generated Project.toml records `Name <mail>` — this is
        # how `config set --mail` and `create --mail` reach PkgTemplates.
        mail = get(merged_options, "mail", nothing)
        if mail isa AbstractString && !isempty(mail)
            authors = get(merged_options, "authors", nothing)
            if authors isa AbstractVector && !isempty(authors)
                merged_options["authors"] = String[
                    occursin('<', String(a)) ? String(a) : "$(String(a)) <$mail>"
                    for a in authors
                ]
            end
        end

        # Promote a config-only license (saved as `license_type` by `config set
        # --license`) into the License plugin section so PackageGenerator picks
        # it up. CLI-supplied License options keep precedence.
        config_license = get(merged_options, "license_type", nothing)
        if config_license !== nothing && config_license != "" &&
           !haskey(plugin_options, "License")
            plugin_options["License"] = Dict{String,Any}("name" => config_license)
        end

        # Normalize the mise toggle: ArgParse stores the CLI flags under
        # "with-mise"/"no-mise" (dashes), while the persisted config key is
        # "with_mise". Reconcile both so the explicit CLI flag wins, which is
        # what the user expects when overriding a saved default.
        if get(args, "no-mise", false) === true
            merged_options["with_mise"] = false
        elseif get(args, "with-mise", false) === true
            merged_options["with_mise"] = true
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

        # Create package
        output_dir = get(merged_options, "output-dir", pwd())
        PackageGenerator.create_package(package_name, merged_options, plugin_options, output_dir)

        # Generate mise config when enabled (default: true if unspecified)
        if get(merged_options, "with_mise", true)
            try
                TemplateManager.generate_mise_config(package_name, merged_options, output_dir)
            catch e
                # Never silently skip Ctrl-C: rethrow so the CLI exits promptly.
                # Other failures only warn, since mise config is best-effort.
                if e isa InterruptException
                    rethrow(e)
                end
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

`JTCError` subtypes carry a curated `message` field that is already
written for the user; surface it directly so we do not double-prefix
the error type or wrap the message in noise like
`Error: PluginOptionFormatError:`.
"""
function handle_error(e::Exception)::CommandResult
    if e isa PackageGenerationError
        return CommandResult(
            success=false,
            message="Package generation failed: $(e.message)"
        )
    elseif e isa JTCError
        return CommandResult(
            success=false,
            message=e.message
        )
    else
        return CommandResult(
            success=false,
            message="Error: $(sprint(showerror, e))"
        )
    end
end

end  # module CreateCommand
