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

Empty pieces (consecutive whitespace) are skipped. Unmatched closing
brackets clamp `bracket_depth` at zero rather than going negative; the
opening-quote character is recorded so a `'` inside a `"..."` block does
not close the quoting context.
"""
function split_string(s::AbstractString)::Vector{String}
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

"""
    parse_kv_string(s::AbstractString)::Dict{String,Any}

Parse a `key=value key2=value2` bundle into a typed Dict. Tokens without
`=` are silently dropped; whitespace around keys and values is stripped;
each value is run through `parse_value` for type coercion.

Returns an empty `Dict` for an empty input or a string with no `=` tokens.
"""
function parse_kv_string(s::AbstractString)::Dict{String,Any}
    options = Dict{String,Any}()
    for part in split_string(s)
        if contains(part, '=')
            k, v = split(part, '=', limit=2)
            options[String(strip(k))] = parse_value(strip(v))
        end
    end
    return options
end

end  # module PluginOptionParser
