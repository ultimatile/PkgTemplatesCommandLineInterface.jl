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

"""
    parse_plugin_option_value(value_str::AbstractString)

Convert a string token into the appropriate Julia type for storage in TOML.
Mirrors `parse_plugin_option_value` in the Python port.
"""
function parse_plugin_option_value(value_str::AbstractString)
    s = String(value_str)
    lower = lowercase(s)
    if lower in ("true", "yes")
        return true
    elseif lower in ("false", "no")
        return false
    elseif startswith(s, "[") && endswith(s, "]")
        inner = strip(s[2:end-1])
        if isempty(inner)
            return String[]
        end
        return [String(strip(strip(item), ['"', '\''])) for item in split(inner, ',')]
    elseif occursin(r"^\d+$", s)
        return parse(Int, s)
    else
        # Decimal-looking values (e.g., "1.2", "1.10") stay strings: downstream
        # plugins such as ProjectFile expect a string they can parse into a
        # VersionNumber, and Float coercion would also drop trailing zeros.
        was_quoted = (startswith(s, '"') && endswith(s, '"')) ||
                     (startswith(s, '\'') && endswith(s, '\''))
        if was_quoted
            s = s[2:end-1]
        end
        # Auto-promote comma-separated strings to arrays for PkgTemplates.jl
        # compatibility — but only when the user did NOT explicitly quote the
        # value. Quotes signal "this is a literal string", so a value like
        # `name="Doe, Jane"` must stay a single string instead of becoming
        # ["Doe", "Jane"] (which would break String-typed fields like Git.name).
        if !was_quoted && occursin(',', s)
            return [String(strip(item)) for item in split(s, ',') if !isempty(strip(item))]
        end
        return s
    end
end

# Split an option string respecting quotes and `[...]` arrays so that
# `--plugin 'a=1 ignore=".vscode,.DS_Store"'` parses cleanly.
function _split_plugin_option_string(s::AbstractString)::Vector{String}
    parts = String[]
    current = IOBuffer()
    in_quotes = false
    quote_char = '\0'
    bracket_depth = 0

    for c in s
        if c in ('"', '\'') && !in_quotes && bracket_depth == 0
            in_quotes = true
            quote_char = c
            print(current, c)
        elseif in_quotes && c == quote_char
            in_quotes = false
            quote_char = '\0'
            print(current, c)
        elseif c == '[' && !in_quotes
            bracket_depth += 1
            print(current, c)
        elseif c == ']' && !in_quotes
            bracket_depth = max(bracket_depth - 1, 0)
            print(current, c)
        elseif c == ' ' && !in_quotes && bracket_depth == 0
            piece = String(strip(String(take!(current))))
            if !isempty(piece)
                push!(parts, piece)
            end
        else
            print(current, c)
        end
    end
    piece = String(strip(String(take!(current))))
    if !isempty(piece)
        push!(parts, piece)
    end
    return parts
end

# Parse a `key=value key2=value2` string into a Dict, with type coercion.
function _parse_plugin_kv_string(s::AbstractString)::Dict{String,Any}
    options = Dict{String,Any}()
    for part in _split_plugin_option_string(s)
        if contains(part, '=')
            k, v = split(part, '=', limit=2)
            options[String(strip(k))] = parse_plugin_option_value(strip(v))
        end
    end
    return options
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

        # ArgParse registers config-set plugin options with `nargs='?'`,
        # `constant=""`, and `default=nothing`, so `value` is one of:
        #   nothing       → option not specified
        #   ""            → specified without a value; enable plugin with defaults
        #   "key=val ..." → specified with a KEY=VALUE bundle
        if value === nothing
            continue
        elseif value isa AbstractString
            section = get(defaults, plugin_name, Dict{String,Any}())
            if !(section isa Dict)
                section = Dict{String,Any}()
            end
            if !isempty(value)
                for (opt_key, opt_val) in _parse_plugin_kv_string(value)
                    section[opt_key] = opt_val
                    push!(messages, "Set default $plugin_name.$opt_key: $(repr(opt_val))")
                end
            end
            defaults[plugin_name] = section
            if isempty(value)
                push!(messages, "Enabled plugin: $plugin_name")
            end
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
        return CommandResult(
            success=false,
            message="Error executing config command: $(sprint(showerror, e))"
        )
    end
end

end  # module ConfigCommand
