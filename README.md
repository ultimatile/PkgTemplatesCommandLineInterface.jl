# PkgTemplatesCommandLineInterface.jl

[![Build Status](https://github.com/ultimatile/PkgTemplatesCommandLineInterface.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ultimatile/PkgTemplatesCommandLineInterface.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A command-line interface for [PkgTemplates.jl](https://github.com/JuliaCI/PkgTemplates.jl).

## Features

- Create Julia packages from the command line without REPL
- User-configurable defaults via TOML config file
- Optional mise task file generation
- Shell completion (fish, bash, zsh)

## Requirements

- Julia 1.12+

## Installation

```bash
julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/ultimatile/PkgTemplatesCommandLineInterface.jl")'
```

### Using mise

```bash
git clone https://github.com/ultimatile/PkgTemplatesCommandLineInterface.jl
cd PkgTemplatesCommandLineInterface.jl
mise run install
```

## Usage

```bash
# Create a package
jtc create MyPackage

# Create with options
jtc create MyPackage --author "Your Name" --user yourgithubuser --output-dir ~/projects

# Generate without mise configuration file
jtc create MyPackage --no-mise

# Dry run (preview without executing)
jtc create MyPackage --dry-run
```

### Commands

| Command | Description |
|---------|-------------|
| `create` | Create a new Julia package |
| `config show` | Show current configuration |
| `config set` | Set configuration values |
| `plugin-info [name]` | Display plugin information |
| `completion <shell>` | Generate shell completion scripts (fish, bash, zsh) |

### Global Options

| Option | Description |
|--------|-------------|
| `--version` | Show version |
| `--verbose, -v` | Enable verbose logging |

## Configuration

jtc supports user-configurable defaults stored in `$XDG_CONFIG_HOME/jtc/config.toml` (default: `~/.config/jtc/config.toml`).

### Setting Defaults

```bash
# Show current configuration
jtc config show

# Set default values
jtc config set --author "Your Name" --user yourgithubuser
```

### Configuration Precedence

1. Command-line options (highest priority)
2. Configuration file defaults
3. Built-in defaults (lowest priority)

### Plugin options and secrets

Plugin fields are passed through to PkgTemplates.jl as `key=value` pairs, e.g.
`jtc create MyPackage --tagbot 'token=GITHUB_TOKEN'`.

Fields typed as a *secret* (such as `TagBot.token` or `TagBot.ssh`) expect the
**name** of a GitHub Actions secret — **not the secret value itself**.
PkgTemplates.jl renders the name into the workflow as `${{ secrets.NAME }}`, so
a conventional value is an identifier like `DOCUMENTER_KEY` or `GITHUB_TOKEN`.

If you accidentally pass a literal credential, jtc warns and avoids echoing it
in command output and `--dry-run` plans. The literal would still be written to
your config file in plaintext, so remove it and use the secret's name instead.
The config file and its directory are created with owner-only permissions
(`0600` / `0700`) on POSIX systems.

## Troubleshooting

### `No such file or directory` error after Julia update

After updating Julia (e.g., `juliaup up`), you may see:

```
/path/to/julia-1.x.x+0.../bin/julia: No such file or directory
```

This occurs because the shim file has a hardcoded path to the old Julia version. Reinstall to fix:

```bash
julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/ultimatile/PkgTemplatesCommandLineInterface.jl")'
```

## License

MIT
