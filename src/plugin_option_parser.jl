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
    parse_kv_string(s::AbstractString; plugin_flag::Union{String,Nothing}=nothing)::Dict{String,Any}

Parse a whitespace-separated `key=value key2=value2` bundle into a typed
Dict. Only tokens that already contain `=` are considered; other tokens
are silently dropped. Within each such token, whitespace around the key
and value is stripped before the value is passed to `parse_value` for
type coercion. This means `key=value` must remain a single token —
whitespace around `=` (for example, `k= v` or `k =v`) will split the
pair across tokens and will not be parsed as a single option.

Throws `PluginOptionFormatError` for the comma-separated KEY=VALUE
anti-pattern, in either shape:
- `aqua=true,project=true` — comma + `=` in one unquoted value
- `aqua=true, project=true` — trailing `,` in one value, the next token
  carries `=` (i.e. the user typed comma + space and got a split that
  hid the original pattern from a single-value check)

`plugin_flag`, when supplied, is the user-visible flag name (e.g.
`"--git"`). It is woven into the canonical-form examples in the error
message so the user can copy/paste the suggestion. Direct callers that
do not know the flag (tests) leave it `nothing`.

Returns an empty `Dict` for an empty input or a string with no `=` tokens.
"""
function parse_kv_string(s::AbstractString;
                          plugin_flag::Union{String,Nothing}=nothing)::Dict{String,Any}
    options = Dict{String,Any}()
    parts = split_string(s)
    n = length(parts)
    for i in 1:n
        part = parts[i]
        if contains(part, '=')
            k, v = split(part, '=', limit=2)
            key = String(strip(k))
            # Drop empty-key tokens (e.g. `=value`, `  =x`) so downstream
            # plugin construction and TOML writes never see an empty
            # option name.
            if !isempty(key)
                stripped_v = String(strip(v))
                next_part = i < n ? parts[i + 1] : ""
                _reject_comma_separated_kv(key, stripped_v, next_part, plugin_flag)
                options[key] = parse_value(stripped_v)
            end
        end
    end
    return options
end

# Reject a comma-separated KEY=VALUE list shape (the clig.dev anti-pattern).
# Two shapes count:
#   1. Single unquoted value contains both `,` and `=`
#      (e.g. `aqua=true,project=true` arrives as one token)
#   2. Value ends with `,` and the *next* token contains `=`
#      (e.g. `aqua=true, project=true` is split into `["aqua=true,", "project=true"]`
#      and neither half on its own would trigger shape #1)
# Quoted values like `name="Doe, Jane"` and bracket arrays like
# `ignore=[a,b]` are explicitly excluded because the comma is part of
# the literal value, not a list-of-KV separator.
function _reject_comma_separated_kv(key::AbstractString,
                                     value::AbstractString,
                                     next_part::AbstractString,
                                     plugin_flag::Union{String,Nothing})
    isempty(value) && return
    quoted = (startswith(value, '"') && endswith(value, '"')) ||
             (startswith(value, '\'') && endswith(value, '\''))
    bracketed = startswith(value, '[') && endswith(value, ']')
    quoted && return
    bracketed && return

    shape_inline = occursin(',', value) && occursin('=', value)
    shape_split = endswith(value, ',') && contains(next_part, '=')

    if shape_inline || shape_split
        # Reconstruct the comma-separated pieces so the suggestion uses
        # exactly what the user typed. For shape_split the second piece
        # comes from the next token (which already contains `=`).
        pieces = if shape_inline
            [String(strip(p)) for p in split(value, ',')]
        else
            base = chopsuffix(value, ",")
            String[String(strip(base)), String(strip(next_part))]
        end
        # Filter out any empty pieces from things like trailing `,,`.
        pieces = filter(!isempty, pieces)

        flag = something(plugin_flag, "--<plugin>")
        # Build the canonical replacement forms with the real flag name
        # so users can copy/paste. The leading piece keeps its key (it
        # came from the offending token); subsequent pieces already
        # carry their own `key=value` syntax so we just emit them.
        repeat_parts = ["$flag $key=$(pieces[1])"]
        append!(repeat_parts, ["$flag $p" for p in pieces[2:end]])
        repeat_form = join(repeat_parts, " ")
        bundle_inner = join(vcat(["$key=$(pieces[1])"], pieces[2:end]), " ")
        bundle_form = "$flag \"$bundle_inner\""

        # Construct the message without leading whitespace so handle_error
        # paths display it cleanly.
        msg = string(
            "Plugin option value ", repr(value), " for key ", repr(key),
            " looks like a comma-separated list of KEY=VALUE pairs, ",
            "which is not supported. Please use one of:\n",
            "  ", repeat_form, "\n",
            "  ", bundle_form,
        )
        throw(PluginOptionFormatError(msg))
    end
    return
end

end  # module PluginOptionParser
