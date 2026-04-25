"""
Tests for PackageGenerator module.

This module tests the core package generation functionality using PkgTemplates.jl,
including plugin instantiation and error handling.
"""

using Test
using PkgTemplatesCommandLineInterface
using PkgTemplates
using TOML

# Import PackageGenerator module
include("../src/package_generator.jl")

@testset "PackageGenerator" begin
    @testset "create_package - basic functionality" begin
        # Test basic package generation with minimal options
        mktempdir() do tmpdir
            name = "TestPackage"
            options = Dict{String,Any}(
                "user" => "testuser",
                "authors" => ["Test Author <test@example.com>"],
                "julia_version" => "1.10"
            )
            plugin_options = Dict{String,Dict{String,Any}}()

            # Execute package generation
            PackageGenerator.create_package(name, options, plugin_options, tmpdir)

            # Verify package directory was created
            pkg_path = joinpath(tmpdir, name)
            @test isdir(pkg_path)

            # Verify Project.toml exists and contains expected data
            project_toml = joinpath(pkg_path, "Project.toml")
            @test isfile(project_toml)

            # Parse and verify contents
            project_data = TOML.parsefile(project_toml)
            @test project_data["name"] == name
            @test haskey(project_data, "uuid")
        end
    end

    @testset "create_package - with plugin options" begin
        # Test package generation with plugin instantiation
        mktempdir() do tmpdir
            name = "TestPackageWithPlugins"
            options = Dict{String,Any}(
                "user" => "testuser",
                "authors" => ["Test Author <test@example.com>"]
            )
            plugin_options = Dict{String,Dict{String,Any}}(
                "Git" => Dict{String,Any}(
                    "manifest" => true,
                    "ssh" => false
                ),
                "Readme" => Dict{String,Any}()
            )

            # Execute package generation with plugins
            PackageGenerator.create_package(name, options, plugin_options, tmpdir)

            # Verify package was created
            pkg_path = joinpath(tmpdir, name)
            @test isdir(pkg_path)

            # Verify Git plugin was applied (should have .git directory)
            @test isdir(joinpath(pkg_path, ".git"))

            # Verify Readme plugin was applied
            @test isfile(joinpath(pkg_path, "README.md"))
        end
    end

    @testset "instantiate_plugins - basic plugins" begin
        # Test plugin instantiation with no options
        plugin_options = Dict{String,Dict{String,Any}}(
            "Readme" => Dict{String,Any}()
        )

        plugins = PackageGenerator.instantiate_plugins(plugin_options)

        @test length(plugins) == 1
        @test plugins[1] isa PkgTemplates.Readme
    end

    @testset "instantiate_plugins - with options" begin
        # Test plugin instantiation with keyword arguments
        plugin_options = Dict{String,Dict{String,Any}}(
            "Git" => Dict{String,Any}(
                "manifest" => true,
                "ssh" => false
            )
        )

        plugins = PackageGenerator.instantiate_plugins(plugin_options)

        @test length(plugins) == 1
        @test plugins[1] isa PkgTemplates.Git
        @test plugins[1].manifest == true
        @test plugins[1].ssh == false
    end

    @testset "instantiate_plugins - multiple plugins" begin
        # Test multiple plugin instantiation
        plugin_options = Dict{String,Dict{String,Any}}(
            "Git" => Dict{String,Any}("manifest" => true),
            "Readme" => Dict{String,Any}(),
            "License" => Dict{String,Any}("name" => "MIT")
        )

        plugins = PackageGenerator.instantiate_plugins(plugin_options)

        @test length(plugins) == 3

        # Check plugin types (order may vary)
        plugin_types = Set(typeof(p) for p in plugins)
        @test PkgTemplates.Git in plugin_types
        @test PkgTemplates.Readme in plugin_types
        @test PkgTemplates.License in plugin_types
    end

    @testset "error handling - PkgTemplates.jl errors" begin
        # Test that PkgTemplates.jl errors are converted to PackageGenerationError
        mktempdir() do tmpdir
            name = "Invalid-Package-Name!"  # Invalid Julia identifier
            options = Dict{String,Any}("user" => "test")
            plugin_options = Dict{String,Dict{String,Any}}()

            # Should throw PackageGenerationError (not raw PkgTemplates error)
            @test_throws PackageGenerationError PackageGenerator.create_package(
                name, options, plugin_options, tmpdir
            )
        end
    end

    @testset "error handling - invalid plugin name" begin
        # Test error when plugin type doesn't exist
        plugin_options = Dict{String,Dict{String,Any}}(
            "NonExistentPlugin" => Dict{String,Any}()
        )

        # Should throw an error (either PluginNotFoundError or caught by instantiate_plugins)
        @test_throws Exception PackageGenerator.instantiate_plugins(plugin_options)
    end

    # Contract: instantiate_plugins reflects on each plugin's field types and
    # adapts the persisted-string representation to whatever the constructor
    # demands. Each test below corresponds to a class of MethodError the
    # earlier review cycle surfaced (TagBot Secret, License.name spurious wrap).
    @testset "instantiate_plugins type adaptation contracts" begin
        @testset "Secret-typed field accepts a stored String" begin
            # PkgTemplates.TagBot has token::Secret. Without auto-wrapping the
            # constructor raises MethodError when reading config-saved tokens.
            plugin_options = Dict{String,Dict{String,Any}}(
                "TagBot" => Dict{String,Any}("token" => "MY_TOKEN")
            )
            plugins = PackageGenerator.instantiate_plugins(plugin_options)
            @test length(plugins) == 1
            @test plugins[1] isa PkgTemplates.TagBot
            @test plugins[1].token isa PkgTemplates.Secret
        end

        @testset "Union{Nothing,Secret} fields also accept stored Strings" begin
            # TagBot.ssh / .gpg are Union{Nothing,Secret}; the wrapping check
            # must use `Secret <: ftype` so these still get adapted.
            plugin_options = Dict{String,Dict{String,Any}}(
                "TagBot" => Dict{String,Any}(
                    "token" => "TKN",
                    "ssh" => "SSH_KEY",
                )
            )
            plugins = PackageGenerator.instantiate_plugins(plugin_options)
            @test plugins[1].ssh isa PkgTemplates.Secret
        end

        @testset "String-typed fields are NOT wrapped in Secret" begin
            # Git has a String-typed `branch` field. A naive `Secret <: ftype`
            # check that fell back to Any when fieldtype lookup failed would
            # wrap the value into Secret and break the kwarg. Guard against
            # that by exercising a real String field on a real plugin.
            plugin_options = Dict{String,Dict{String,Any}}(
                "Git" => Dict{String,Any}("branch" => "main")
            )
            plugins = PackageGenerator.instantiate_plugins(plugin_options)
            @test plugins[1] isa PkgTemplates.Git
            @test plugins[1].branch == "main"
            @test plugins[1].branch isa AbstractString
        end

        @testset "kwarg-only license name is not coerced into Secret" begin
            # License accepts a `name` kwarg even though it has no `name`
            # field; this is the case that originally over-triggered the
            # Secret wrap when `fieldtype` defaulted to `Any`. The contract
            # is that License instantiation must succeed unchanged.
            plugin_options = Dict{String,Dict{String,Any}}(
                "License" => Dict{String,Any}("name" => "MIT")
            )
            plugins = PackageGenerator.instantiate_plugins(plugin_options)
            @test plugins[1] isa PkgTemplates.License
        end
    end
end
