using JuliaPkgTemplatesCommandLineInterface
using Test
using Aqua

@testset "JuliaPkgTemplatesCommandLineInterface.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(JuliaPkgTemplatesCommandLineInterface)
    end
    # Write your tests here.
end
