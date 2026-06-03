"""
ConfigManager module for XDG-compliant configuration file management.

Provides functions for loading, saving, and managing TOML configuration files
following the XDG Base Directory specification.
"""
module ConfigManager

using TOML

"""
    get_config_path(custom_path::Union{String,Nothing}=nothing)::String

Resolve the configuration file path.

When `custom_path` is provided, returns its absolute, tilde-expanded form
without creating any directories — callers are responsible for `mkpath` on
save. With no argument, follows the XDG Base Directory specification:
respects `XDG_CONFIG_HOME` (defaults to `~/.config`), appends `jtc`, and
creates the directory when missing.

# Arguments
- `custom_path::Union{String,Nothing}`: Optional override (e.g., from `--config-file`)

# Returns
- `String`: Absolute path to the configuration file

# Example
```julia
ConfigManager.get_config_path()
# "/home/user/.config/jtc/config.toml"

ConfigManager.get_config_path("~/custom/jtc.toml")
# "/home/user/custom/jtc.toml"
```
"""
function get_config_path(custom_path::Union{String,Nothing}=nothing)::String
    # If a custom path is supplied, normalise it but do not create the parent
    # directory yet — that is the caller's responsibility on save.
    if custom_path !== nothing
        return abspath(expanduser(custom_path))
    end

    # Get XDG_CONFIG_HOME or default to ~/.config
    xdg_config_home = get(ENV, "XDG_CONFIG_HOME", nothing)
    config_dir = if xdg_config_home !== nothing
        xdg_config_home
    else
        joinpath(homedir(), ".config")
    end

    # Application-specific config directory
    app_config_dir = joinpath(config_dir, "jtc")

    # Create directory if it doesn't exist
    mkpath(app_config_dir)

    # The config may persist secret *names* (and, by user mistake, secret
    # values). Lock the directory to the owner so co-located users on a shared
    # host cannot read it. Idempotent; best-effort on platforms where chmod
    # only toggles the read-only bit (e.g. Windows).
    try
        chmod(app_config_dir, 0o700)
    catch e
        e isa InterruptException && rethrow(e)
    end

    return joinpath(app_config_dir, "config.toml")
end

"""
    create_default_config()::Dict{String, Any}

Create a default configuration dictionary.

# Returns
- `Dict{String, Any}`: Default configuration with empty author, user, mail,
  and mise settings

# Example
```julia
default = ConfigManager.create_default_config()
# Returns: Dict("default" => Dict("author" => "", ...))
```
"""
function create_default_config()::Dict{String,Any}
    return Dict{String,Any}(
        "default" => Dict{String,Any}(
            "author" => "",
            "user" => "",
            "mail" => "",
            "mise_filename_base" => ".mise",
            "with_mise" => true
        )
    )
end

"""
    save_config(config::Dict{String, Any}, custom_path::Union{String,Nothing}=nothing)::Nothing

Save configuration to a TOML file.

Uses `sorted=true` for stable output order. The destination is
`get_config_path(custom_path)` and its parent directory is created on
demand, so a custom path pointing inside a non-existent folder is fine.

# Arguments
- `config::Dict{String, Any}`: Configuration dictionary to save
- `custom_path::Union{String,Nothing}`: Optional override (e.g., from `--config-file`)

# Note
TOML.jl does not preserve comments in config files. This is a known limitation.

# Example
```julia
config = Dict("default" => Dict("author" => "Jane Doe"))
ConfigManager.save_config(config)

# Write to a non-default location:
ConfigManager.save_config(config, "~/custom/jtc.toml")
```
"""
function save_config(config::Dict{String,Any}, custom_path::Union{String,Nothing}=nothing)::Nothing
    config_path = get_config_path(custom_path)

    # Ensure parent directory exists when writing to a user-specified location
    mkpath(dirname(config_path))

    open(config_path, "w") do io
        # sorted=true ensures stable output order for easier testing and diffs
        TOML.print(io, config, sorted=true)
    end

    # Restrict the file to owner read/write: it may hold secret names and, when
    # a user misunderstands a Secret field, literal credentials. Applied after
    # write, so a brief umask-dependent window exists — acceptable for a
    # single-user dotfile. Best-effort: chmod is a no-op-ish on Windows.
    try
        chmod(config_path, 0o600)
    catch e
        e isa InterruptException && rethrow(e)
    end

    @info "Configuration saved to $config_path"
    return nothing
end

"""
    load_config(custom_path::Union{String,Nothing}=nothing)::Dict{String, Any}

Load configuration from a TOML file.

Reads from `get_config_path(custom_path)`. If the file doesn't exist,
writes and returns a default configuration. If parsing fails, logs a
warning and returns the default without saving.

# Arguments
- `custom_path::Union{String,Nothing}`: Optional override (e.g., from `--config-file`)

# Returns
- `Dict{String, Any}`: Loaded or default configuration

# Error Handling
- File not found: Creates default config and saves it (at `custom_path` when provided)
- Parse error: Logs warning, returns default config (does not save)

# Example
```julia
config = ConfigManager.load_config()
author = config["default"]["author"]

# Read from a custom location:
config = ConfigManager.load_config("~/custom/jtc.toml")
```
"""
function load_config(custom_path::Union{String,Nothing}=nothing)::Dict{String,Any}
    config_path = get_config_path(custom_path)

    if isfile(config_path)
        # Try to parse the file
        result = TOML.tryparsefile(config_path)

        if result isa TOML.ParserError
            # Log error details
            @error "Failed to parse config file: $config_path" exception = result
            @warn "Using default configuration"
            return create_default_config()
        end

        return result
    else
        # File doesn't exist, create default
        default_config = create_default_config()
        save_config(default_config, custom_path)
        return default_config
    end
end

"""
    merge_config(config_defaults::Dict, cli_args::Dict)::Dict

Merge configuration defaults with CLI arguments.

CLI arguments take precedence over config defaults. `nothing` values in
`cli_args` do not override existing values. Nested dictionaries are merged
recursively.

# Arguments
- `config_defaults::Dict`: Configuration from file (or defaults)
- `cli_args::Dict`: Arguments from command line

# Returns
- `Dict`: Merged configuration with CLI arguments taking precedence

# Priority
CLI arguments > Configuration file defaults

# Example
```julia
defaults = Dict("author" => "Default", "user" => "default_user")
cli = Dict("author" => "CLI Author", "user" => nothing)
merged = ConfigManager.merge_config(defaults, cli)
# merged["author"] == "CLI Author" (CLI overrides)
# merged["user"] == "default_user" (nothing doesn't override)
```
"""
function merge_config(config_defaults::Dict, cli_args::Dict)::Dict
    merged = copy(config_defaults)

    for (key, value) in cli_args
        if haskey(merged, key) && value isa Dict && merged[key] isa Dict
            # Recursively merge nested dictionaries
            merged[key] = merge(merged[key], value)
        elseif value !== nothing
            # CLI argument overrides (but nothing doesn't override)
            merged[key] = value
        end
        # If value is nothing, preserve the default
    end

    return merged
end

end  # module ConfigManager
