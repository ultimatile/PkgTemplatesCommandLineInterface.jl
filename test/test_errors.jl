using Test
using JuliaPkgTemplatesCommandLineInterface

@testset "Custom Error Types" begin
    @testset "JTCError abstract type" begin
        # JTCError should be a subtype of Exception
        @test JTCError <: Exception

        # All custom errors should be subtypes of JTCError
        @test JuliaDependencyError <: JTCError
        @test PackageGenerationError <: JTCError
        @test ConfigurationError <: JTCError
        @test TemplateGenerationError <: JTCError
        @test PluginNotFoundError <: JTCError
    end

    @testset "JuliaDependencyError" begin
        err = JuliaDependencyError("Julia 1.12+ is required")
        @test err.message == "Julia 1.12+ is required"

        # Test that it can be thrown and caught
        @test_throws JuliaDependencyError throw(err)

        # Test error message display
        io = IOBuffer()
        showerror(io, err)
        output = String(take!(io))
        @test occursin("JuliaDependencyError", output)
        @test occursin("Julia 1.12+ is required", output)
    end

    @testset "PackageGenerationError" begin
        err = PackageGenerationError("Failed to generate package")
        @test err.message == "Failed to generate package"
        @test err.cause === nothing

        # Test with cause
        cause = ErrorException("Original error")
        err_with_cause = PackageGenerationError("Failed to generate package"; cause=cause)
        @test err_with_cause.message == "Failed to generate package"
        @test err_with_cause.cause === cause

        # Test error message display
        io = IOBuffer()
        showerror(io, err)
        output = String(take!(io))
        @test occursin("PackageGenerationError", output)
        @test occursin("Failed to generate package", output)
    end

    @testset "ConfigurationError" begin
        config_path = "/path/to/config.toml"
        err = ConfigurationError("Invalid TOML syntax", config_path)
        @test err.message == "Invalid TOML syntax"
        @test err.config_path == config_path

        # Test error message display
        io = IOBuffer()
        showerror(io, err)
        output = String(take!(io))
        @test occursin("ConfigurationError", output)
        @test occursin("Invalid TOML syntax", output)
        @test occursin(config_path, output)
    end

    @testset "TemplateGenerationError" begin
        template_path = "/path/to/template.mustache"
        err = TemplateGenerationError("Template not found", template_path)
        @test err.message == "Template not found"
        @test err.template_path == template_path

        # Test error message display
        io = IOBuffer()
        showerror(io, err)
        output = String(take!(io))
        @test occursin("TemplateGenerationError", output)
        @test occursin("Template not found", output)
        @test occursin(template_path, output)
    end

    @testset "PluginNotFoundError" begin
        plugin_name = "NonExistentPlugin"
        available = ["Git", "Formatter", "License"]
        err = PluginNotFoundError(plugin_name, available)
        @test err.plugin_name == plugin_name
        @test err.available_plugins == available

        # Test error message display
        io = IOBuffer()
        showerror(io, err)
        output = String(take!(io))
        @test occursin("PluginNotFoundError", output)
        @test occursin(plugin_name, output)
        @test occursin("Available plugins", output)
        for plugin in available
            @test occursin(plugin, output)
        end
    end

    @testset "Error hierarchy polymorphism" begin
        # All custom errors can be caught as JTCError
        errors = [
            JuliaDependencyError("test"),
            PackageGenerationError("test"),
            ConfigurationError("test", "/path"),
            TemplateGenerationError("test", "/path"),
            PluginNotFoundError("test", String[])
        ]

        for err in errors
            caught = false
            try
                throw(err)
            catch e
                if e isa JTCError
                    caught = true
                end
            end
            @test caught
        end
    end
end
