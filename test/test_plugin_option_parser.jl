"""
Tests for PluginOptionParser module.

Locks in the contract that both `create` and `config set` consume: a single
`KEY=VALUE` bundle string parses identically across both commands. The
parser's behaviour was audited under issue #9 and every case below must
keep matching across future edits.
"""

using Test
using PkgTemplatesCommandLineInterface
import PkgTemplatesCommandLineInterface.PluginOptionParser

@testset "PluginOptionParser" begin
    # Contract: parse_value preserves the user's intent across types —
    # bools, ints, decimals (kept as strings so VersionNumber survives),
    # bracket arrays, comma-promoted arrays, and quoted strings.
    @testset "parse_value contracts" begin
        @testset "boolean synonyms cover true/yes/false/no but not 0/1" begin
            @test PluginOptionParser.parse_value("true") === true
            @test PluginOptionParser.parse_value("YES") === true
            @test PluginOptionParser.parse_value("false") === false
            @test PluginOptionParser.parse_value("No") === false
            # `1`/`0` must round-trip as integers so plugin int options like
            # `indent=1` don't become booleans.
            @test PluginOptionParser.parse_value("1") === 1
            @test PluginOptionParser.parse_value("0") === 0
        end

        @testset "integer values keep their type" begin
            @test PluginOptionParser.parse_value("42") === 42
            @test PluginOptionParser.parse_value("100") === 100
        end

        @testset "decimal-shaped values stay strings" begin
            # ProjectFile.version expects a string parseable into VersionNumber;
            # Float coercion both breaks the constructor and loses trailing zeros.
            @test PluginOptionParser.parse_value("1.10") == "1.10"
            @test PluginOptionParser.parse_value("1.10") isa AbstractString
            @test PluginOptionParser.parse_value("1.2") == "1.2"
        end

        @testset "bracket-form arrays parse to Vector{String}" begin
            @test PluginOptionParser.parse_value("[a,b,c]") == ["a", "b", "c"]
            @test PluginOptionParser.parse_value("[]") == String[]
            # Quoted items inside brackets keep their internal text
            @test PluginOptionParser.parse_value("[\"a b\",c]") == ["a b", "c"]
        end

        @testset "unquoted comma values stay strings (bracket form is canonical)" begin
            # Issue #5: list values use bracket form only. A bare
            # `a,b,c` is no longer auto-promoted; it stays the literal
            # string. (`parse_kv_string` will refuse to call this with
            # such a value at all — top-level commas are rejected up
            # front — but the contract for parse_value alone remains
            # well-defined.)
            @test PluginOptionParser.parse_value("a,b,c") == "a,b,c"
            @test PluginOptionParser.parse_value(".DS_Store,.vscode") ==
                  ".DS_Store,.vscode"
        end

        @testset "quoted strings keep commas as literal text" begin
            # Without this contract, Git.name="Doe, Jane" silently becomes a
            # Vector{String} and the plugin constructor fails.
            @test PluginOptionParser.parse_value("\"Doe, Jane\"") == "Doe, Jane"
            @test PluginOptionParser.parse_value("'a, b, c'") == "a, b, c"
        end

        @testset "plain strings flow through unchanged" begin
            @test PluginOptionParser.parse_value("blue") == "blue"
            @test PluginOptionParser.parse_value("MyPkg") == "MyPkg"
        end
    end

    # Contract: split_string respects quotes and brackets so multi-key
    # bundles never lose tokens to whitespace inside a single value.
    @testset "split_string contracts" begin
        @testset "splits unquoted tokens on whitespace" begin
            @test PluginOptionParser.split_string("a=1 b=2") == ["a=1", "b=2"]
        end

        @testset "preserves whitespace inside double quotes" begin
            @test PluginOptionParser.split_string("name=\"Doe, Jane\" k=v") ==
                  ["name=\"Doe, Jane\"", "k=v"]
        end

        @testset "preserves whitespace inside single quotes" begin
            @test PluginOptionParser.split_string("a='1 2' b=3") == ["a='1 2'", "b=3"]
        end

        @testset "preserves whitespace inside brackets" begin
            @test PluginOptionParser.split_string("ignore=[.DS_Store, .vscode] k=v") ==
                  ["ignore=[.DS_Store, .vscode]", "k=v"]
        end

        @testset "skips consecutive whitespace runs" begin
            @test PluginOptionParser.split_string("a=1   b=2") == ["a=1", "b=2"]
        end

        @testset "treats tabs and newlines as separators" begin
            # The docstring claims "whitespace" splitting; pasted multiline
            # input must parse the same as single-line.
            @test PluginOptionParser.split_string("a=1\tb=2") == ["a=1", "b=2"]
            @test PluginOptionParser.split_string("a=1\nb=2") == ["a=1", "b=2"]
            @test PluginOptionParser.split_string("a=1\t\nb=2  c=3") ==
                  ["a=1", "b=2", "c=3"]
        end

        @testset "apostrophe in unquoted value is literal, not a delimiter" begin
            # Without the at-token-start guard, the `'` after `O` would
            # open a quoted block and swallow ` email=x` into the name
            # value, dropping the email entirely.
            @test PluginOptionParser.split_string("name=O'Connor email=x") ==
                  ["name=O'Connor", "email=x"]
            # Same idea with double quote inside an unquoted value.
            @test PluginOptionParser.split_string("k=he\"said k2=v2") ==
                  ["k=he\"said", "k2=v2"]
        end

        @testset "quote at start-of-token still opens a quoted block" begin
            # The token-start guard must not regress the canonical case:
            # quoted values that contain whitespace or commas survive intact.
            @test PluginOptionParser.split_string("name=\"Doe, Jane\" k=v") ==
                  ["name=\"Doe, Jane\"", "k=v"]
            @test PluginOptionParser.split_string("a='1 2' b=3") ==
                  ["a='1 2'", "b=3"]
            # A quoted token that is not preceded by `=` (just whitespace).
            @test PluginOptionParser.split_string("'literal token' k=v") ==
                  ["'literal token'", "k=v"]
        end

        @testset "empty input yields empty vector" begin
            @test PluginOptionParser.split_string("") == String[]
            @test PluginOptionParser.split_string("   ") == String[]
        end
    end

    # Contract: parse_kv_string composes split_string and parse_value into
    # a single typed Dict, dropping malformed (no `=`) tokens silently.
    @testset "parse_kv_string contracts" begin
        @testset "empty string yields empty Dict" begin
            @test PluginOptionParser.parse_kv_string("") == Dict{String,Any}()
        end

        @testset "single KEY=VALUE pair" begin
            @test PluginOptionParser.parse_kv_string("ssh=true") ==
                  Dict{String,Any}("ssh" => true)
        end

        @testset "multiple pairs" begin
            result = PluginOptionParser.parse_kv_string("ssh=true manifest=false")
            @test result == Dict{String,Any}("ssh" => true, "manifest" => false)
        end

        @testset "issue #9: quoted comma preserved as single string" begin
            # Acceptance criterion: `--git 'name="Doe, Jane" email=x'` must
            # preserve `name` as a single string, not split it on the comma.
            result = PluginOptionParser.parse_kv_string("name=\"Doe, Jane\" email=x")
            @test result["name"] == "Doe, Jane"
            @test result["email"] == "x"
        end

        @testset "issue #9: bracket array round-trips" begin
            # Acceptance criterion: `--git 'ignore=[.DS_Store, .vscode]'`
            # must arrive at PkgTemplates as Vector{String}.
            result = PluginOptionParser.parse_kv_string("ignore=[.DS_Store, .vscode]")
            @test result["ignore"] == [".DS_Store", ".vscode"]
        end

        @testset "issue #9: version-like value stays String" begin
            # Acceptance criterion: `--projectfile version=1.10` must reach
            # ProjectFile as the string "1.10", not Float64(1.1).
            result = PluginOptionParser.parse_kv_string("version=1.10")
            @test result["version"] == "1.10"
            @test result["version"] isa AbstractString
        end

        @testset "trailing whitespace tolerated" begin
            @test PluginOptionParser.parse_kv_string("k=v  ") ==
                  Dict{String,Any}("k" => "v")
        end

        @testset "mixed quote types coexist" begin
            result = PluginOptionParser.parse_kv_string("a='1' b=\"2\"")
            @test result["a"] == "1"
            @test result["b"] == "2"
        end

        @testset "= inside quoted value preserved" begin
            result = PluginOptionParser.parse_kv_string("k=\"val=with=equals\"")
            @test result["k"] == "val=with=equals"
        end

        @testset "tokens without = are silently dropped" begin
            # `standalone` has no `=`, so it should not produce a Dict entry
            # (it cannot meaningfully map to a key/value pair).
            @test PluginOptionParser.parse_kv_string("standalone") == Dict{String,Any}()
            # But a real KV next to a malformed token still produces the KV.
            @test PluginOptionParser.parse_kv_string("standalone k=v") ==
                  Dict{String,Any}("k" => "v")
        end

        @testset "apostrophe inside value preserved as literal" begin
            # End-to-end invariant: a literal `'` mid-value must not
            # swallow following options. Previously this corruption
            # silently dropped `email`.
            result = PluginOptionParser.parse_kv_string("name=O'Connor email=x")
            @test result["name"] == "O'Connor"
            @test result["email"] == "x"
        end

        @testset "empty-key tokens are dropped" begin
            # `=value` (and similar) must not produce a Dict entry under
            # the empty-string key — that would silently corrupt downstream
            # plugin construction and TOML writes.
            @test PluginOptionParser.parse_kv_string("=value") == Dict{String,Any}()
            @test PluginOptionParser.parse_kv_string("  =x") == Dict{String,Any}()
            # A real KV alongside an empty-key token still parses cleanly.
            @test PluginOptionParser.parse_kv_string("=junk k=v") ==
                  Dict{String,Any}("k" => "v")
        end

        # Issue #5 contract: any top-level comma in a plugin option
        # bundle is the KV-separator anti-pattern (clig.dev) and must
        # raise a friendly `PluginOptionFormatError`. Only commas inside
        # a `"..."`/`'...'` quote or a `[...]` bracket are legitimate.
        @testset "issue #5: error message names the input and a canonical form" begin
            # Without a flag, the suggestion uses the `<plugin>` placeholder.
            err = try
                PluginOptionParser.parse_kv_string("aqua=true,project=true")
                nothing
            catch e
                e
            end
            @test err isa PluginOptionFormatError
            @test occursin("aqua=true,project=true", err.message)
            @test occursin("--", err.message)
            # The plain bundle and bracket-form list both appear in the
            # canonical-form examples.
            @test occursin("\"key1=val1 key2=val2\"", err.message)
            @test occursin("[item1, item2]", err.message)

            # When the caller knows the real flag, the suggestion uses it.
            err_with_flag = try
                PluginOptionParser.parse_kv_string("aqua=true,project=true";
                                                    plugin_flag="--tests")
                nothing
            catch e
                e
            end
            @test err_with_flag isa PluginOptionFormatError
            @test occursin("--tests", err_with_flag.message)
            @test !occursin("<plugin>", err_with_flag.message)
        end

        @testset "issue #5: pure list value as bare comma string is now rejected" begin
            # Previously `ignore=.DS_Store,.vscode` round-tripped as a
            # Vector via the comma-promotion shortcut. With list values
            # restricted to bracket form, this top-level comma is the
            # KV-separator anti-pattern and must be rejected uniformly.
            @test_throws PluginOptionFormatError PluginOptionParser.parse_kv_string(
                "ignore=.DS_Store,.vscode",
            )
        end

        @testset "issue #5: legitimate comma uses keep working" begin
            # Quoted comma — single literal string, not a list.
            @test PluginOptionParser.parse_kv_string("name=\"Doe, Jane\"") ==
                  Dict{String,Any}("name" => "Doe, Jane")

            # Bracket array — the only canonical list-value syntax.
            @test PluginOptionParser.parse_kv_string("ignore=[.DS_Store, .vscode]") ==
                  Dict{String,Any}("ignore" => [".DS_Store", ".vscode"])

            # Bracket array containing `=`-looking text inside an item.
            # The comma is inside the bracket, so the top-level scan
            # leaves it alone.
            @test PluginOptionParser.parse_kv_string("items=[a=1, b=2]") ==
                  Dict{String,Any}("items" => ["a=1", "b=2"])
        end

        @testset "issue #5: every whitespace variant of comma-KV rejected uniformly" begin
            # The unified top-level-comma rule must catch all four shapes
            # discovered during the review-pipeline (which previously
            # required four separate checks).
            for malformed in (
                "aqua=true,project=true",     # no whitespace
                "aqua=true, project=true",    # space after comma
                "aqua=true ,project=true",    # space before comma
                "aqua=true , project=true",   # space on both sides
            )
                @test_throws PluginOptionFormatError PluginOptionParser.parse_kv_string(
                    malformed,
                )
            end
        end
    end
end
