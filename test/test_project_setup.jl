using Test
using TOML

@testset "Project Setup Tests" begin
    project_toml_path = joinpath(@__DIR__, "..", "Project.toml")
    @test isfile(project_toml_path)

    project = TOML.parsefile(project_toml_path)

    @testset "Julia version requirement" begin
        @test haskey(project, "compat")
        @test haskey(project["compat"], "julia")

        # Julia version should be >= 1.12
        julia_version = project["compat"]["julia"]
        @test occursin(r"1\.1[2-9]|1\.[2-9][0-9]|[2-9]\.", julia_version) || julia_version == "1.12"
    end

    @testset "Apps configuration" begin
        @test haskey(project, "apps")
        @test haskey(project["apps"], "jtc")
    end

    @testset "Required dependencies" begin
        @test haskey(project, "deps")
        required_deps = ["ArgParse", "Mustache", "PkgTemplates", "TOML"]

        for dep in required_deps
            @test haskey(project["deps"], dep)
        end
    end

    @testset "Directory structure" begin
        @test isdir(joinpath(@__DIR__, "..", "src"))
        @test isdir(joinpath(@__DIR__, "..", "test"))
        @test isdir(joinpath(@__DIR__, "..", "src", "templates"))
    end
end
