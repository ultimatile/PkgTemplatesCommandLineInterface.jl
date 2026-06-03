"""
PluginDiscovery module for PkgTemplates.jl plugin dynamic discovery.

Provides functions for discovering available plugins, extracting metadata,
and detecting zero-argument plugins.
"""
module PluginDiscovery

using PkgTemplates
using PkgTemplatesCommandLineInterface: PluginDetails, PluginNotFoundError

"""
    get_plugins()::Vector{Type{<:PkgTemplates.Plugin}}

Get all concrete plugin types from PkgTemplates.jl.

Uses the official `PkgTemplates.concretes()` API to recursively discover
all concrete plugin types, sorted alphabetically by name.

# Returns
- `Vector{Type{<:PkgTemplates.Plugin}}`: Sorted list of all plugin types

# Example
```julia
plugins = PluginDiscovery.get_plugins()
# Returns: [AppVeyor, BlueStyleBadge, CirrusCI, ...]
```
"""
function get_plugins()::Vector{Type{<:PkgTemplates.Plugin}}
    return PkgTemplates.concretes(PkgTemplates.Plugin)
end

"""
    is_argumentless_plugin(PluginType::Type{<:PkgTemplates.Plugin})::Bool

Check if a plugin has a zero-argument constructor.

Attempts to instantiate the plugin with zero arguments. Returns `true` if
successful, `false` if a `MethodError` is raised.

# Arguments
- `PluginType::Type{<:PkgTemplates.Plugin}`: Plugin type to check

# Returns
- `Bool`: `true` if plugin can be instantiated with zero arguments

# Example
```julia
PluginDiscovery.is_argumentless_plugin(PkgTemplates.Readme)
# Returns: true

PluginDiscovery.is_argumentless_plugin(PkgTemplates.Git)
# Returns: true (all PkgTemplates.jl plugins have zero-arg constructors)
```
"""
function is_argumentless_plugin(PluginType::Type{<:PkgTemplates.Plugin})::Bool
    try
        # Attempt to instantiate with zero arguments
        PluginType()
        return true
    catch e
        if e isa MethodError
            return false
        else
            # Re-throw unexpected errors
            rethrow(e)
        end
    end
end

"""
    canonical_names()::Dict{String,String}

Build a `lowercase => canonical` lookup for every plugin type discovered via
`get_plugins()`. Used by both `config set` and `create` so CLI keys (which
ArgParse stores as lowercase, e.g. `"git"`) can be mapped back to the names
PkgTemplates expects (`"Git"`).

Returns an empty `Dict` when plugin discovery throws at runtime (for example,
if `get_plugins()` / `PkgTemplates.concretes(PkgTemplates.Plugin)` raises
while enumerating plugin types). Callers must treat unknown plugin keys as
a no-op rather than an error to preserve graceful degradation.
"""
function canonical_names()::Dict{String,String}
    plugin_names = String[]
    try
        for p in get_plugins()
            push!(plugin_names, string(nameof(p)))
        end
    catch e
        # Never swallow user cancellation: rethrow Ctrl-C so the CLI can
        # exit promptly. Other failures fall through to a graceful empty
        # mapping so callers treat unknown plugin keys as a no-op.
        if e isa InterruptException
            rethrow(e)
        end
        return Dict{String,String}()
    end
    sort!(plugin_names)
    return Dict(lowercase(n) => n for n in plugin_names)
end

"""
    get_plugin_details(plugin_name::String)::PluginDetails

Get detailed metadata for a specific plugin.

Extracts field names, types, and default values using PkgTemplates.jl's
reflection API (`fieldnames`, `fieldtype`, `defaultkw`).

# Arguments
- `plugin_name::String`: Name of the plugin (e.g., "Git", "License")

# Returns
- `PluginDetails`: Metadata including name, fields, types, and defaults

# Throws
- `PluginNotFoundError`: If plugin name doesn't exist

# Example
```julia
details = PluginDiscovery.get_plugin_details("Git")
# Returns: PluginDetails with Git plugin metadata
```
"""
function get_plugin_details(plugin_name::String)::PluginDetails
    # Try to get the plugin type
    PluginType = try
        getfield(PkgTemplates, Symbol(plugin_name))
    catch e
        if e isa UndefVarError
            # Plugin not found, provide helpful error
            available_plugins = String[String(nameof(p)) for p in get_plugins()]
            throw(PluginNotFoundError(plugin_name, available_plugins))
        else
            rethrow(e)
        end
    end

    # Verify it's actually a Plugin subtype
    if !(PluginType <: PkgTemplates.Plugin)
        available_plugins = String[String(nameof(p)) for p in get_plugins()]
        throw(PluginNotFoundError(plugin_name, available_plugins))
    end

    # Extract field information
    field_names = fieldnames(PluginType)
    fields = Symbol[f for f in field_names]  # Ensure Vector{Symbol}
    field_types = Type[fieldtype(PluginType, f) for f in fields]

    # Extract default values using PkgTemplates.defaultkw
    default_values = Any[]
    for f in fields
        default_val = try
            # Try using PkgTemplates.defaultkw (official API for @plugin macro)
            PkgTemplates.defaultkw(PluginType, Val(f))
        catch e
            # Never swallow user cancellation: rethrow Ctrl-C so the CLI can
            # exit promptly. Any other failure falls through to the
            # zero-arg-constructor fallback, then to `nothing` if that
            # also fails.
            if e isa InterruptException
                rethrow(e)
            end
            # Fallback: try instantiating with zero arguments
            if is_argumentless_plugin(PluginType)
                instance = PluginType()
                getfield(instance, f)
            else
                # If all else fails, return nothing
                nothing
            end
        end
        push!(default_values, default_val)
    end

    return PluginDetails(
        name=plugin_name,
        fields=fields,
        types=field_types,
        defaults=default_values
    )
end

"""
    is_secret_field(plugin_name::AbstractString, key::AbstractString)::Bool

Report whether `plugin_name`'s field `key` is typed to hold a
`PkgTemplates.Secret` (e.g. `TagBot.token`, `TagBot.ssh`).

A `Secret` field expects the *name* of a GitHub Actions secret, never the
literal credential — PkgTemplates renders it as `\${{ secrets.NAME }}`. This
predicate lets the CLI single out those fields so it can warn on, or redact,
values that were mistakenly supplied as literals.

Unlike the Secret-wrapping check in `PackageGenerator.instantiate_plugins`,
this intentionally does not also require `!(String <: ftype)`: a field that
accepts either a `String` or a `Secret` is still sensitive enough to flag.

Returns `false` for unknown plugins or fields so callers can treat the result
as a pure hint without guarding against plugin-discovery failures.
"""
function is_secret_field(plugin_name::AbstractString, key::AbstractString)::Bool
    PluginType = try
        getfield(PkgTemplates, Symbol(plugin_name))
    catch e
        e isa InterruptException && rethrow(e)
        return false
    end
    (PluginType isa Type && PluginType <: PkgTemplates.Plugin) || return false
    sym = Symbol(key)
    sym in fieldnames(PluginType) || return false
    return PkgTemplates.Secret <: fieldtype(PluginType, sym)
end

"""
    looks_like_secret_value(value)::Bool

Heuristically decide whether `value` looks like a *literal* credential rather
than the secret *name* a `Secret` field expects.

True for well-known credential prefixes (GitHub tokens, PEM/OpenSSH key
headers) and for generic high-entropy blobs (length ≥ 32 with mixed letters
and digits and no whitespace). A conventional secret name such as
`DOCUMENTER_KEY` or `GITHUB_TOKEN` is short and digit-free, so it does not
trip the generic branch — keeping false positives low.

This is a guardrail, not a guarantee: it powers warnings and dry-run redaction,
never a hard refusal, so occasional misses are acceptable.
"""
function looks_like_secret_value(value)::Bool
    value isa AbstractString || return false
    s = String(value)
    for p in ("ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_")
        startswith(s, p) && return true
    end
    startswith(s, "-----BEGIN") && return true  # PEM / OpenSSH private key blob
    # Generic high-entropy blob: long, no whitespace, mixed letters and digits.
    length(s) >= 32 || return false
    occursin(r"\s", s) && return false
    return occursin(r"[A-Za-z]", s) && occursin(r"[0-9]", s)
end

end  # module PluginDiscovery
