"""
Tests for PluginDiscovery module.

Tests PkgTemplates.jl plugin dynamic discovery, metadata extraction,
and zero-argument plugin detection.
"""

using Test
using PkgTemplatesCommandLineInterface
using PkgTemplates

# Import PluginDiscovery (will be defined in src/plugin_discovery.jl)
include("../src/plugin_discovery.jl")

@testset "PluginDiscovery" begin
    @testset "get_plugins()" begin
        @testset "returns all concrete plugin types" begin
            plugins = PluginDiscovery.get_plugins()

            # Should return a vector of plugin types
            @test plugins isa Vector{Type{<:PkgTemplates.Plugin}}

            # Should have multiple plugins (PkgTemplates.jl has ~20+ plugins)
            @test length(plugins) > 20

            # Should include common plugins
            plugin_names = Set(nameof.(plugins))
            @test :Git in plugin_names
            @test :License in plugin_names
            @test :Readme in plugin_names
            @test :Tests in plugin_names
            @test :Formatter in plugin_names
            @test :GitHubActions in plugin_names
        end

        @testset "returns plugins in sorted order" begin
            plugins = PluginDiscovery.get_plugins()
            plugin_names = nameof.(plugins)

            # Should be sorted alphabetically
            @test issorted(plugin_names)
        end

        @testset "all returned types are subtypes of Plugin" begin
            plugins = PluginDiscovery.get_plugins()

            for plugin in plugins
                @test plugin <: PkgTemplates.Plugin
            end
        end
    end

    @testset "is_argumentless_plugin()" begin
        @testset "returns true for plugins with zero-argument constructors" begin
            # Test with known zero-argument plugins
            @test PluginDiscovery.is_argumentless_plugin(PkgTemplates.Readme) == true
            @test PluginDiscovery.is_argumentless_plugin(PkgTemplates.SrcDir) == true
            @test PluginDiscovery.is_argumentless_plugin(PkgTemplates.Git) == true
            @test PluginDiscovery.is_argumentless_plugin(PkgTemplates.License) == true
        end

        @testset "handles all plugins correctly" begin
            plugins = PluginDiscovery.get_plugins()

            for plugin in plugins
                # Should not throw an error
                result = PluginDiscovery.is_argumentless_plugin(plugin)

                # Result should be a boolean
                @test result isa Bool

                # If true, should be able to instantiate with zero arguments
                if result
                    instance = plugin()
                    @test instance isa PkgTemplates.Plugin
                end
            end
        end
    end

    @testset "get_plugin_details()" begin
        @testset "returns correct metadata for Git plugin" begin
            details = PluginDiscovery.get_plugin_details("Git")

            @test details isa PluginDetails
            @test details.name == "Git"

            # Git has multiple fields
            @test length(details.fields) > 0
            @test :manifest in details.fields
            @test :ssh in details.fields

            # Types should match field count
            @test length(details.types) == length(details.fields)

            # Defaults should match field count
            @test length(details.defaults) == length(details.fields)
        end

        @testset "returns correct metadata for License plugin" begin
            details = PluginDiscovery.get_plugin_details("License")

            @test details isa PluginDetails
            @test details.name == "License"

            # License has fields like name, path, destination
            @test length(details.fields) > 0

            # All arrays should have same length
            @test length(details.types) == length(details.fields)
            @test length(details.defaults) == length(details.fields)
        end

        @testset "returns correct metadata for Readme plugin" begin
            details = PluginDiscovery.get_plugin_details("Readme")

            @test details isa PluginDetails
            @test details.name == "Readme"

            # Readme has fields
            @test length(details.fields) > 0

            # Consistency checks
            @test length(details.types) == length(details.fields)
            @test length(details.defaults) == length(details.fields)
        end

        @testset "extracts default values using defaultkw" begin
            details = PluginDiscovery.get_plugin_details("Git")

            # Find manifest field
            manifest_idx = findfirst(==(Symbol("manifest")), details.fields)
            @test manifest_idx !== nothing

            # Default value for Git.manifest should be false (based on PkgTemplates.jl)
            @test details.defaults[manifest_idx] == false

            # Find ssh field
            ssh_idx = findfirst(==(Symbol("ssh")), details.fields)
            @test ssh_idx !== nothing

            # Default value for Git.ssh should be false
            @test details.defaults[ssh_idx] == false
        end

        @testset "extracts field types correctly" begin
            details = PluginDiscovery.get_plugin_details("Git")

            # Find manifest field (should be Bool)
            manifest_idx = findfirst(==(Symbol("manifest")), details.fields)
            @test details.types[manifest_idx] == Bool

            # Find ssh field (should be Bool)
            ssh_idx = findfirst(==(Symbol("ssh")), details.fields)
            @test details.types[ssh_idx] == Bool
        end

        @testset "throws PluginNotFoundError for non-existent plugin" begin
            available_plugins = String[String(nameof(p)) for p in PluginDiscovery.get_plugins()]

            @test_throws PluginNotFoundError PluginDiscovery.get_plugin_details("NonExistentPlugin")

            # Error should include available plugins
            try
                PluginDiscovery.get_plugin_details("NonExistentPlugin")
                @test false  # Should not reach here
            catch e
                @test e isa PluginNotFoundError
                @test e.plugin_name == "NonExistentPlugin"
                @test !isempty(e.available_plugins)
            end
        end

        @testset "handles all discovered plugins" begin
            plugins = PluginDiscovery.get_plugins()

            for plugin in plugins
                plugin_name = String(nameof(plugin))
                details = PluginDiscovery.get_plugin_details(plugin_name)

                @test details.name == plugin_name
                @test length(details.fields) == length(details.types)
                @test length(details.fields) == length(details.defaults)

                # All types should be Type objects
                for t in details.types
                    @test t isa Type
                end
            end
        end
    end

    @testset "canonical_names()" begin
        @testset "maps lowercase plugin names back to canonical PkgTemplates names" begin
            mapping = PluginDiscovery.canonical_names()

            # Common plugins must be present and round-trip correctly.
            @test mapping["git"] == "Git"
            @test mapping["license"] == "License"
            @test mapping["readme"] == "Readme"
            @test mapping["formatter"] == "Formatter"
        end

        @testset "covers every plugin returned by get_plugins" begin
            plugins = PluginDiscovery.get_plugins()
            mapping = PluginDiscovery.canonical_names()

            # Every discovered plugin must appear in the mapping under its
            # lowercase name and round-trip back to its canonical spelling.
            for p in plugins
                name = string(nameof(p))
                @test mapping[lowercase(name)] == name
            end

            # And the mapping should contain exactly that many entries.
            @test length(mapping) == length(plugins)
        end
    end

    # Contract: catch blocks that fall back to a default (returning empty
    # mappings, swallowing failure into warnings, etc.) must never absorb
    # `InterruptException`. Otherwise a Ctrl-C during plugin discovery is
    # silently turned into a partial/empty result and the CLI keeps running
    # past where the user asked it to stop. Surfaced by Copilot review on
    # PR #8 (canonical_names case); this test guards the contract repo-wide
    # against the kind of catch that swallowed it.
    @testset "catch-all blocks rethrow InterruptException" begin
        # Files that historically contained catch-everything blocks for
        # graceful degradation. Each must guard against absorbing Ctrl-C.
        for relpath in ("src/plugin_discovery.jl", "src/create_command.jl")
            path = joinpath(@__DIR__, "..", relpath)
            src = read(path, String)
            # Look for a `catch` block that does NOT bind the exception,
            # which is the strongest "swallow everything" smell.
            bare_catches = collect(eachmatch(r"\bcatch\b(?![^\n]*[A-Za-z_])", src))
            @test isempty(bare_catches)
            # Any catch that does bind must mention InterruptException —
            # either to rethrow it, or to dispatch on it. Files with no
            # catch blocks at all trivially satisfy this.
            if occursin(r"\bcatch\s+\w", src)
                @test occursin("InterruptException", src)
            end
        end
    end

    @testset "Integration: plugin discovery and instantiation" begin
        @testset "can instantiate all zero-argument plugins" begin
            plugins = PluginDiscovery.get_plugins()

            for plugin in plugins
                if PluginDiscovery.is_argumentless_plugin(plugin)
                    # Should be able to instantiate
                    instance = plugin()
                    @test instance isa PkgTemplates.Plugin
                end
            end
        end

        @testset "plugin details match actual plugin structure" begin
            # Test with Git plugin
            details = PluginDiscovery.get_plugin_details("Git")

            # Create instance
            git_instance = PkgTemplates.Git()

            # All fields in details should exist on instance
            for field in details.fields
                @test hasproperty(git_instance, field)
            end

            # Field count should match
            @test length(details.fields) == length(fieldnames(PkgTemplates.Git))
        end
    end

    @testset "is_secret_field()" begin
        # TagBot.token / TagBot.ssh are Secret-typed (render as ${{ secrets.X }}).
        @test PluginDiscovery.is_secret_field("TagBot", "token")
        @test PluginDiscovery.is_secret_field("TagBot", "ssh")
        # Plain fields are not.
        @test !PluginDiscovery.is_secret_field("License", "name")
        @test !PluginDiscovery.is_secret_field("Git", "ssh")
        # Unknown plugin / field degrade to false rather than throwing.
        @test !PluginDiscovery.is_secret_field("NoSuchPlugin", "token")
        @test !PluginDiscovery.is_secret_field("TagBot", "no_such_field")
    end

    @testset "looks_like_secret_value()" begin
        # Conventional secret *names* must not trip the heuristic.
        @test !PluginDiscovery.looks_like_secret_value("DOCUMENTER_KEY")
        @test !PluginDiscovery.looks_like_secret_value("GITHUB_TOKEN")
        @test !PluginDiscovery.looks_like_secret_value("")
        # Known credential prefixes are flagged regardless of length.
        @test PluginDiscovery.looks_like_secret_value("ghp_0123456789abcdef")
        @test PluginDiscovery.looks_like_secret_value("github_pat_11ABCDEFG")
        @test PluginDiscovery.looks_like_secret_value("-----BEGIN OPENSSH PRIVATE KEY-----")
        # Generic high-entropy blob (>=32, mixed letters+digits, no whitespace).
        @test PluginDiscovery.looks_like_secret_value("a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7")
        # Long but digit-free identifier is treated as a name, not a value.
        @test !PluginDiscovery.looks_like_secret_value("A_VERY_LONG_DESCRIPTIVE_SECRET_NAME")
        # Non-strings are never secret-shaped.
        @test !PluginDiscovery.looks_like_secret_value(true)
        @test !PluginDiscovery.looks_like_secret_value(42)
    end
end
