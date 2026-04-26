"""
PluginOptionParser module — single source of truth for converting plugin
option strings (`KEY=VALUE` bundles) into typed Julia values.

Both `CreateCommand` (CLI plugin options) and `ConfigCommand` (`config set`
plugin options) consume the same shape — a single optional space-separated
string per `--plugin` flag — so they must parse it identically. Routing
both modules through this parser prevents the divergence that issue #9
documented (Float coercion, missing quote handling, etc.).
"""
module PluginOptionParser

import ..PkgTemplatesCommandLineInterface: PluginOptionFormatError

export parse_value, split_string, parse_kv_string

"""
    parse_value(value_str::AbstractString)

Convert a single value token into the appropriate Julia type:
- `"true"` / `"yes"` (case-insensitive) → `true`
- `"false"` / `"no"` (case-insensitive) → `false`
- `"[a, b, c]"` (bracket form) → `Vector{String}`, with surrounding quotes
  on each item stripped
- `"123"` (digits only) → `Int`
- Decimal-looking values (e.g. `"1.2"`, `"1.10"`) **stay strings**, since
  downstream plugins such as `ProjectFile` expect a string parsable as
  `VersionNumber` and Float coercion would drop trailing zeros.
- An explicitly quoted string (`"..."` or `'...'`) has its quotes stripped
  and is returned as a single string, even if it contains commas.
- An unquoted comma-separated value is auto-promoted to `Vector{String}`
  for PkgTemplates.jl compatibility.
- Any other input is returned as a String unchanged.
"""
function parse_value(value_str::AbstractString)
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
        was_quoted = (startswith(s, '"') && endswith(s, '"')) ||
                     (startswith(s, '\'') && endswith(s, '\''))
        if was_quoted
            s = s[2:end-1]
        end
        # Auto-promote comma-separated values to arrays — but only when the
        # user did NOT explicitly quote the value. Quotes signal "this is
        # a literal string", so a value like `name="Doe, Jane"` must stay
        # a single string instead of becoming ["Doe", "Jane"] (which would
        # break String-typed fields like Git.name).
        if !was_quoted && occursin(',', s)
            return [String(strip(item)) for item in split(s, ',') if !isempty(strip(item))]
        end
        return s
    end
end

"""
    split_string(s::AbstractString)::Vector{String}

Split a plugin option bundle on whitespace while respecting `"..."`,
`'...'`, and `[...]` so that values like `name="Doe, Jane"` or
`ignore=[.DS_Store, .vscode]` survive intact.

A `'` or `"` only opens a quoted block when it appears at the start of
a token — that is, immediately after whitespace, `=`, or the start of
the input. Inside a value (e.g. `name=O'Connor`) an apostrophe is a
literal character and does not affect splitting. Empty pieces from
consecutive whitespace are skipped. Unmatched closing brackets clamp
`bracket_depth` at zero rather than going negative; the opening-quote
character is recorded so a `'` inside a `"..."` block does not close
the quoting context.
"""
function split_string(s::AbstractString)::Vector{String}
    parts = String[]
    current = IOBuffer()
    in_quotes = false
    quote_char = '\0'
    bracket_depth = 0
    prev_char = '\0'  # '\0' marks start-of-input

    for c in s
        # A quote char only opens a quoted block at the start of a token,
        # i.e. right after whitespace, `=`, or the start of input. Without
        # this guard, `name=O'Connor email=x` would enter quote mode at
        # the apostrophe and silently swallow the rest of the bundle.
        at_token_start = prev_char == '\0' || isspace(prev_char) || prev_char == '='

        if c in ('"', '\'') && !in_quotes && bracket_depth == 0 && at_token_start
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
        elseif isspace(c) && !in_quotes && bracket_depth == 0
            # Treat any whitespace (spaces, tabs, newlines) as a separator
            # so pasted multiline bundles parse the same as single-line ones.
            piece = String(strip(String(take!(current))))
            if !isempty(piece)
                push!(parts, piece)
            end
        else
            print(current, c)
        end
        prev_char = c
    end
    piece = String(strip(String(take!(current))))
    if !isempty(piece)
        push!(parts, piece)
    end
    return parts
end

"""
    parse_kv_string(s::AbstractString)::Dict{String,Any}

Parse a whitespace-separated `key=value key2=value2` bundle into a typed
Dict. Only tokens that already contain `=` are considered; other tokens
are silently dropped. Within each such token, whitespace around the key
and value is stripped before the value is passed to `parse_value` for
type coercion. This means `key=value` must remain a single token —
whitespace around `=` (for example, `k= v` or `k =v`) will split the
pair across tokens and will not be parsed as a single option.

Throws `PluginOptionFormatError` when an unquoted value contains both
`,` and `=`. That shape (e.g. `aqua=true,project=true`) almost always
means the user tried to comma-separate KEY=VALUE pairs, which clig.dev
flags as an anti-pattern. The error message points the user at the
canonical forms.

Returns an empty `Dict` for an empty input or a string with no `=` tokens.
"""
function parse_kv_string(s::AbstractString)::Dict{String,Any}
    options = Dict{String,Any}()
    for part in split_string(s)
        if contains(part, '=')
            k, v = split(part, '=', limit=2)
            key = String(strip(k))
            # Drop empty-key tokens (e.g. `=value`, `  =x`) so downstream
            # plugin construction and TOML writes never see an empty
            # option name.
            if !isempty(key)
                stripped_v = String(strip(v))
                _reject_comma_separated_kv(key, stripped_v)
                options[key] = parse_value(stripped_v)
            end
        end
    end
    return options
end

# Reject a comma-separated KEY=VALUE list shape (the clig.dev anti-pattern).
# The signal is "unquoted value that contains both `,` and `=`": a quoted
# value like `name="Doe, Jane"` is a literal string, and a list value like
# `ignore=.DS_Store,.vscode` has a comma but no `=` in the value side.
function _reject_comma_separated_kv(key::AbstractString, value::AbstractString)
    isempty(value) && return
    quoted = (startswith(value, '"') && endswith(value, '"')) ||
             (startswith(value, '\'') && endswith(value, '\''))
    bracketed = startswith(value, '[') && endswith(value, ']')
    if !quoted && !bracketed && occursin(',', value) && occursin('=', value)
        # Reconstruct what the user most likely typed for the friendly
        # message, and offer the two canonical alternatives.
        plugin_hint = "<plugin>"
        # Build the suggested repeat-flag form by splitting the malformed
        # value on commas and pairing each piece with the original key
        # only for the leading piece (subsequent pieces already carry
        # their own `=`, so we emit them as separate flags).
        pieces = String.(split(value, ','))
        repeat_form = "--$plugin_hint $key=$(strip(pieces[1]))"
        for p in pieces[2:end]
            repeat_form *= " --$plugin_hint $(strip(p))"
        end
        bundle_form = "--$plugin_hint \"$key=$(strip(pieces[1]))" *
                      join([" $(strip(p))" for p in pieces[2:end]]) * "\""
        msg = """
            Plugin option value $(repr(value)) for key $(repr(key)) looks like a
            comma-separated list of KEY=VALUE pairs, which is not supported.
            Please use one of:
              $repeat_form
              $bundle_form"""
        throw(PluginOptionFormatError(msg))
    end
    return
end

end  # module PluginOptionParser
