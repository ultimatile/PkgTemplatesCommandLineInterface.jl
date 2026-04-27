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
  on each item stripped. **Bracket form is the only canonical list-value
  syntax**; comma-separated unquoted strings are not promoted to arrays
  (issue #5: top-level commas are reserved for the rejected
  KEY=VALUE-separator anti-pattern).
- `"123"` (digits only) → `Int`
- Decimal-looking values (e.g. `"1.2"`, `"1.10"`) **stay strings**, since
  downstream plugins such as `ProjectFile` expect a string parsable as
  `VersionNumber` and Float coercion would drop trailing zeros.
- An explicitly quoted string (`"..."` or `'...'`) has its quotes stripped
  and is returned as a single string, even if it contains commas.
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

Throws `PluginOptionFormatError` if the bundle contains any top-level
comma — that is, a `,` that is not inside a `"..."` or `'...'` quoted
substring or a `[...]` bracket. With list values restricted to bracket
form (`ignore=[a, b, c]`), a top-level comma always signals the
KEY=VALUE-separator anti-pattern (`a=1,b=2`) and is rejected uniformly
regardless of the surrounding whitespace. Legitimate uses of `,`
(quoted strings, bracket arrays) keep working unchanged.

`plugin_flag`, when supplied, is the user-visible flag name (e.g.
`"--git"`). It is woven into the canonical-form examples in the error
message so the user can copy/paste the suggestion. Direct callers that
do not know the flag (tests) leave it `nothing`.

Returns an empty `Dict` for an empty input or a string with no `=` tokens.
"""
function parse_kv_string(s::AbstractString;
                          plugin_flag::Union{String,Nothing}=nothing)::Dict{String,Any}
    _reject_top_level_comma(s, plugin_flag)
    options = Dict{String,Any}()
    for part in split_string(s)
        if contains(part, '=')
            k, v = split(part, '=', limit=2)
            key = String(strip(k))
            # Drop empty-key tokens (e.g. `=value`, `  =x`) so downstream
            # plugin construction and TOML writes never see an empty
            # option name.
            if !isempty(key)
                options[key] = parse_value(strip(v))
            end
        end
    end
    return options
end

# Reject any top-level comma in a plugin option bundle. "Top-level" means
# outside any `"..."` / `'...'` quoted substring and outside any `[...]`
# bracket. Detection mirrors `split_string`'s quote/bracket bookkeeping
# (in particular: a `'` or `"` only opens a quoted block at the start of
# a token, so apostrophes inside values like `name=O'Connor` are literal
# and do not affect comma detection).
function _reject_top_level_comma(s::AbstractString,
                                  plugin_flag::Union{String,Nothing})
    in_quotes = false
    quote_char = '\0'
    bracket_depth = 0
    prev_char = '\0'

    for c in s
        at_token_start = prev_char == '\0' || isspace(prev_char) || prev_char == '='

        if c in ('"', '\'') && !in_quotes && bracket_depth == 0 && at_token_start
            in_quotes = true
            quote_char = c
        elseif in_quotes && c == quote_char
            in_quotes = false
            quote_char = '\0'
        elseif c == '[' && !in_quotes
            bracket_depth += 1
        elseif c == ']' && !in_quotes
            bracket_depth = max(bracket_depth - 1, 0)
        elseif c == ',' && !in_quotes && bracket_depth == 0
            flag = something(plugin_flag, "--<plugin>")
            msg = string(
                "Plugin option bundle ", repr(String(s)),
                " contains a top-level `,`, which is not supported. ",
                "Use one of:\n",
                "  multiple flags:  ", flag, " key1=val1 ", flag, " key2=val2\n",
                "  one bundle:      ", flag, " \"key1=val1 key2=val2\"\n",
                "  list value:      ", flag, " \"key=[item1, item2]\"",
            )
            throw(PluginOptionFormatError(msg))
        end
        prev_char = c
    end
    return
end

end  # module PluginOptionParser
