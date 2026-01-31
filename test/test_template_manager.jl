"""
Tests for TemplateManager module.

Covers template generation functionality including mise configuration
and shell completion script generation.
"""

using Test
using JuliaPkgTemplatesCommandLineInterface

# Access TemplateManager through parent module
const TemplateManager = JuliaPkgTemplatesCommandLineInterface.TemplateManager

@testset "TemplateManager Tests" begin
    @testset "generate_mise_config" begin
        @testset "generates valid mise configuration file" begin
            mktempdir() do tmpdir
                package_name = "TestPackage"
                options = Dict{String,Any}(
                    "mise_filename_base" => ".mise"
                )

                # Execute generation in temporary directory
                cd(tmpdir) do
                    # Create package directory
                    mkdir(package_name)

                    # Generate mise config
                    TemplateManager.generate_mise_config(package_name, options)

                    # Verify file was created
                    mise_path = joinpath(package_name, ".mise.toml")
                    @test isfile(mise_path)

                    # Verify content
                    content = read(mise_path, String)
                    @test occursin("TestPackage", content)
                    @test occursin("[tasks.test]", content)
                    @test occursin("[tasks.build]", content)
                    @test occursin("[tasks.dev]", content)
                end
            end
        end

        @testset "supports custom mise filename base" begin
            mktempdir() do tmpdir
                package_name = "CustomPackage"
                options = Dict{String,Any}(
                    "mise_filename_base" => ".custom"
                )

                cd(tmpdir) do
                    mkdir(package_name)
                    TemplateManager.generate_mise_config(package_name, options)

                    # Verify custom filename
                    mise_path = joinpath(package_name, ".custom.toml")
                    @test isfile(mise_path)
                end
            end
        end

        @testset "throws TemplateGenerationError on missing template" begin
            mktempdir() do tmpdir
                package_name = "ErrorPackage"
                options = Dict{String,Any}()

                cd(tmpdir) do
                    mkdir(package_name)

                    # Temporarily rename template to simulate missing file
                    template_path = joinpath(
                        dirname(dirname(@__FILE__)),
                        "src", "templates", "mise.toml.mustache"
                    )

                    if isfile(template_path)
                        backup_path = template_path * ".backup"
                        mv(template_path, backup_path)

                        try
                            @test_throws TemplateGenerationError TemplateManager.generate_mise_config(
                                package_name,
                                options
                            )
                        finally
                            # Restore template
                            mv(backup_path, template_path)
                        end
                    end
                end
            end
        end
    end

    @testset "generate_completion" begin
        @testset "generates fish completion script" begin
            plugin_names = ["Git", "Formatter", "License", "Readme"]

            result = TemplateManager.generate_completion("fish", plugin_names)

            # Verify it's a string
            @test result isa String
            @test !isempty(result)

            # Verify fish shell syntax
            @test occursin("complete -c jtc", result)

            # Verify each subcommand is present (they are on separate lines)
            @test occursin("create", result)
            @test occursin("config", result)
            @test occursin("plugin-info", result)
            @test occursin("completion", result)

            # Verify plugin names are included
            for plugin in plugin_names
                @test occursin(plugin, result)
            end
        end

        @testset "handles empty plugin list" begin
            result = TemplateManager.generate_completion("fish", String[])

            @test result isa String
            @test occursin("complete -c jtc", result)
        end

        @testset "throws TemplateGenerationError for unsupported shell" begin
            # Template file doesn't exist for powershell
            @test_throws TemplateGenerationError TemplateManager.generate_completion(
                "powershell",
                ["Git"]
            )
        end
    end
end
