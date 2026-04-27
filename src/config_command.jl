"""
ConfigCommand module for managing CLI configuration commands.

Handles 'config show' and 'config set' subcommands for configuration management.
Mirrors the behaviour of the Python port (JuliaPkgTemplatesCLI).
"""
module ConfigCommand

using TOML

# Import from parent module
using ..PkgTemplatesCommandLineInterface: CommandResult, JTCError, ConfigurationError
import ..ConfigManager
import ..PluginDiscovery
import ..PluginOptionParser

"""
    format_config(config::Dict{String, Any})::String

Format configuration dictionary as TOML string for display.
"""
function format_config(config::Dict{String,Any})::String
    io = IOBuffer()
    TOML.print(io, config, sorted=true)
    return String(take!(io))
end

"""
    update_config(existing_config::Dict, new_values::Dict)::Dict

Merge new configuration values into the `default` section of `existing_config`.

Supports dot notation (e.g., `"formatter.style"`) for nested plugin entries.
Special command-related keys are ignored so a raw ArgParse dict can be passed in.
"""
function update_config(existing_config::Dict, new_values::Dict)::Dict
    updated = deepcopy(existing_config)

    if !haskey(updated, "default")
        updated["default"] = Dict{String,Any}()
    end

    # Compute the plugin-name lookup once per call so callers passing many
    # dotted keys do not re-run PkgTemplates plugin discovery for each one.
    canonical = PluginDiscovery.canonical_names()

    for (key, value) in new_values
        if key in ("show", "set", "%COMMAND%", "%SUBCOMMAND%", "config-file")
            continue
        end

        if contains(key, '.')
            parts = split(key, '.', limit=2)
            section = _resolve_section_target(updated["default"],
                                              String(parts[1]); canonical=canonical)
            option = String(parts[2])
            section_dict = get!(updated["default"], section, Dict{String,Any}())
            if !(section_dict isa Dict)
                section_dict = Dict{String,Any}()
                updated["default"][section] = section_dict
            end
            section_dict[option] = value
        else
            updated["default"][key] = value
        end
    end

    return updated
end

# Pick where to write a dotted-section update. Prefer an existing section
# (case-insensitive match) so legacy lowercase entries keep being updated
# in place; otherwise fall back to the canonical PkgTemplates plugin name
# so new entries land under the form CreateCommand recognises (`Formatter`,
# not `formatter`). For non-plugin sections we keep the literal name.
#
# `canonical` should be the result of `PluginDiscovery.canonical_names()`
# cached by the caller, so multi-key callers pay plugin discovery exactly once.
function _resolve_section_target(defaults::Dict, section::AbstractString;
                                  canonical::Dict{String,String}=PluginDiscovery.canonical_names())::String
    s = String(section)
    if haskey(defaults, s) && defaults[s] isa Dict
        return s
    end
    for k in keys(defaults)
        if k isa AbstractString && lowercase(k) == lowercase(s) &&
           defaults[k] isa Dict
            return String(k)
        end
    end
    return get(canonical, lowercase(s), s)
end

# Apply parsed `config set` arguments to the in-memory config dict.
# Returns (updated_config, messages::Vector{String}).
function _apply_set_args(config::Dict{String,Any}, sub_args::Dict{String,Any})
    if !haskey(config, "default")
        config["default"] = Dict{String,Any}()
    end
    defaults = config["default"]
    messages = String[]

    # --author can repeat; ArgParse gives Vector{Any}/Vector{String}.
    # Direct callers (tests, dispatch_command) may also pass a single String.
    raw_authors = get(sub_args, "author", nothing)
    author_inputs = if raw_authors isa AbstractVector
        raw_authors
    elseif raw_authors isa AbstractString && !isempty(raw_authors)
        Any[raw_authors]
    else
        nothing
    end
    if author_inputs !== nothing && !isempty(author_inputs)
        expanded = String[]
        for a in author_inputs
            for piece in split(String(a), ',')
                stripped = strip(piece)
                if !isempty(stripped)
                    push!(expanded, String(stripped))
                end
            end
        end
        if length(expanded) == 1
            defaults["author"] = expanded[1]
            push!(messages, "Set default author: $(expanded[1])")
        elseif length(expanded) > 1
            defaults["author"] = expanded
            push!(messages, "Set default author(s): $(join(expanded, ", "))")
        end
    end

    # Simple scalar mappings (CLI key => config key)
    scalar_map = (
        ("user", "user"),
        ("mail", "mail"),
        ("license", "license_type"),
        ("julia-version", "julia_version"),
        ("mise-filename-base", "mise_filename_base"),
    )
    for (cli_key, cfg_key) in scalar_map
        v = get(sub_args, cli_key, nothing)
        if v !== nothing
            defaults[cfg_key] = v
            push!(messages, "Set default $(cfg_key): $v")
        end
    end

    # --with-mise / --no-mise are mutually exclusive store_true flags
    if get(sub_args, "with-mise", false) === true
        defaults["with_mise"] = true
        push!(messages, "Set default with_mise: true")
    elseif get(sub_args, "no-mise", false) === true
        defaults["with_mise"] = false
        push!(messages, "Set default with_mise: false")
    end

    # Plugin options: any CLI key matching a known plugin name (case-insensitive),
    # plus legacy dot-notation keys (e.g., `formatter.style => "blue"`) for
    # direct callers that still pass the flat update_config shape.
    canonical = PluginDiscovery.canonical_names()
    for (key, value) in sub_args
        key_str = String(key)

        # Skip already-handled keys and meta-keys
        if key_str in ("author", "user", "mail", "license", "julia-version",
                       "mise-filename-base", "with-mise", "no-mise",
                       "config-file", "%COMMAND%")
            continue
        end

        # Support dotted legacy updates that don't go through the plugin
        # canonical mapping. Preserves prior `update_config` behaviour for
        # mixed CLI/legacy callers, and resolves the section target so
        # plugin defaults reach the create flow under the expected key.
        if contains(key_str, '.')
            parts = split(key_str, '.', limit=2)
            section = _resolve_section_target(defaults, String(parts[1]);
                                              canonical=canonical)
            option = String(parts[2])
            section_dict = get(defaults, section, nothing)
            if !(section_dict isa Dict)
                section_dict = Dict{String,Any}()
                defaults[section] = section_dict
            end
            section_dict[option] = value
            push!(messages, "Set default $section.$option: $(repr(value))")
            continue
        end

        if !haskey(canonical, lowercase(key_str))
            continue
        end
        plugin_name = canonical[lowercase(key_str)]

        # ArgParse registers config-set plugin options with `:append_arg`,
        # `nargs='?'`, `constant=""`, `default=nothing`, so `value` is one of:
        #   nothing       → option not specified (or [] under :append_arg default)
        #   ""            → single bare flag; enable plugin with defaults
        #   "k=v ..."     → single bundle (legacy shape from direct callers)
        #   Vector        → one element per `--<plugin>` invocation; merge
        #                   left-to-right with last-wins on duplicate keys
        section = get(defaults, plugin_name, Dict{String,Any}())
        if !(section isa Dict)
            section = Dict{String,Any}()
        end

        elements = if value === nothing
            String[]
        elseif value isa AbstractString
            String[String(value)]
        elseif value isa AbstractVector
            String[String(e) for e in value if e isa AbstractString]
        else
            String[]
        end

        isempty(elements) && continue

        any_value_set = false
        any_bare_flag = false
        flag = "--$(lowercase(key_str))"
        for elem in elements
            if isempty(elem)
                any_bare_flag = true
            else
                for (opt_key, opt_val) in PluginOptionParser.parse_kv_string(elem; plugin_flag=flag)
                    section[opt_key] = opt_val
                    push!(messages, "Set default $plugin_name.$opt_key: $(repr(opt_val))")
                    any_value_set = true
                end
            end
        end
        defaults[plugin_name] = section
        if any_bare_flag && !any_value_set
            # Bare `--plugin` only (no KV bundle) → record the enable.
            push!(messages, "Enabled plugin: $plugin_name")
        end
    end

    return config, messages
end

"""
    execute(args::Dict{String, Any})::CommandResult

Execute the `config` command, dispatching to `show` or `set`.

The `args` dict is the parsed-args sub-tree for `config` produced by ArgParse.
ArgParse exposes the chosen subcommand under `%COMMAND%`, with that
subcommand's own arguments under `args[subcommand]`.
"""
function execute(args::Dict{String,Any})::CommandResult
    try
        # Determine subcommand. ArgParse uses `%COMMAND%`, but we keep
        # `%SUBCOMMAND%` as a backward-compatible alias for direct callers.
        subcommand = get(args, "%COMMAND%", get(args, "%SUBCOMMAND%", "show"))

        # Sub-args may be nested (CLI path) or flat (legacy/test path).
        sub_args = if haskey(args, subcommand) && args[subcommand] isa Dict
            convert(Dict{String,Any}, args[subcommand])
        else
            args
        end

        custom_path = get(sub_args, "config-file", nothing)

        if subcommand == "show"
            config = ConfigManager.load_config(custom_path)
            print(format_config(config))
            return CommandResult(success=true)

        elseif subcommand == "set"
            config = ConfigManager.load_config(custom_path)

            # CLI integration path: option keys come from ArgParse and are
            # mapped explicitly. We still support a legacy direct-dict shape
            # by falling back to update_config when no recognised CLI keys
            # are present.
            cli_keys = ("author", "user", "mail", "license", "julia-version",
                        "mise-filename-base", "with-mise", "no-mise")
            plugin_canonical_names = PluginDiscovery.canonical_names()
            uses_cli_shape = any(haskey(sub_args, k) for k in cli_keys) ||
                             any(haskey(plugin_canonical_names, lowercase(String(k)))
                                 for k in keys(sub_args))

            if uses_cli_shape
                config, msgs = _apply_set_args(config, sub_args)
                ConfigManager.save_config(config, custom_path)
                for m in msgs
                    println(m)
                end
                return CommandResult(success=true,
                                     message="Configuration updated successfully")
            else
                updated_config = update_config(config, sub_args)
                ConfigManager.save_config(updated_config, custom_path)
                return CommandResult(success=true,
                                     message="Configuration updated successfully")
            end

        else
            return CommandResult(
                success=false,
                message="Unknown config subcommand: $subcommand"
            )
        end

    catch e
        # JTCError messages are user-facing strings already; surface them
        # directly so the friendly text is not buried under
        # "Error executing config command: PluginOptionFormatError:" noise.
        if e isa JTCError
            return CommandResult(success=false, message=e.message)
        end
        return CommandResult(
            success=false,
            message="Error executing config command: $(sprint(showerror, e))"
        )
    end
end

end  # module ConfigCommand
