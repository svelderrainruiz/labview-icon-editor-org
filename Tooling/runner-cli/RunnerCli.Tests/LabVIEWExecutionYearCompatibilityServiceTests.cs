using RunnerCli;

namespace RunnerCli.Tests;

public class LabVIEWExecutionYearCompatibilityServiceTests
{
    [Fact]
    public void Resolve_honors_execution_year_override_env_var()
    {
        using var repoFixture = CreateRepoFixture("20.0");
        using var envOverride = new EnvironmentVariableOverride(
            LabVIEWExecutionYearCompatibilityService.ExecutionYearOverrideEnvVar,
            "2020");

        var result = LabVIEWExecutionYearCompatibilityService.Resolve(
            sourceLabviewVersion: "20.0",
            repoRoot: repoFixture.RepoRoot,
            commandLabel: "ppl build");

        Assert.Equal("20.0", result.SourceVersion.Raw);
        Assert.Equal("2020", result.SourceVersion.Year);
        Assert.Equal("2020", result.ExecutionYear);
        Assert.False(result.CompatMappingApplied);
    }

    [Fact]
    public void Resolve_throws_on_invalid_execution_year_override_env_var()
    {
        using var repoFixture = CreateRepoFixture("20.0");
        using var envOverride = new EnvironmentVariableOverride(
            LabVIEWExecutionYearCompatibilityService.ExecutionYearOverrideEnvVar,
            "twenty-twenty");

        Assert.Throws<InvalidOperationException>(() =>
            LabVIEWExecutionYearCompatibilityService.Resolve(
                sourceLabviewVersion: "20.0",
                repoRoot: repoFixture.RepoRoot,
                commandLabel: "ppl build"));
    }

    [Fact]
    public void Resolve_maps_lv2020_source_to_lv2026_execution_year()
    {
        using var repoFixture = CreateRepoFixture("20.0");

        var result = LabVIEWExecutionYearCompatibilityService.Resolve(
            sourceLabviewVersion: "20.0",
            repoRoot: repoFixture.RepoRoot,
            commandLabel: "ppl build");

        Assert.Equal("20.0", result.SourceVersion.Raw);
        Assert.Equal("2020", result.SourceVersion.Year);
        Assert.Equal("2026", result.ExecutionYear);
        Assert.True(result.CompatMappingApplied);
    }

    [Fact]
    public void Resolve_keeps_non_lv2020_source_year_as_execution_year()
    {
        using var repoFixture = CreateRepoFixture("26.1");

        var result = LabVIEWExecutionYearCompatibilityService.Resolve(
            sourceLabviewVersion: "26.1",
            repoRoot: repoFixture.RepoRoot,
            commandLabel: "vip build");

        Assert.Equal("26.1", result.SourceVersion.Raw);
        Assert.Equal("2026", result.SourceVersion.Year);
        Assert.Equal("2026", result.ExecutionYear);
        Assert.False(result.CompatMappingApplied);
    }

    [Fact]
    public void Resolve_throws_when_source_version_mismatches_lvversion_contract()
    {
        using var repoFixture = CreateRepoFixture("20.0");

        Assert.ThrowsAny<Exception>(() =>
            LabVIEWExecutionYearCompatibilityService.Resolve(
                sourceLabviewVersion: "26.1",
                repoRoot: repoFixture.RepoRoot,
                commandLabel: "ppl build"));
    }

    private static RepoFixture CreateRepoFixture(string lvversionRaw)
    {
        var temp = Directory.CreateTempSubdirectory("lvie-exec-year");
        File.WriteAllText(Path.Combine(temp.FullName, ".lvversion"), lvversionRaw);
        return new RepoFixture(temp);
    }

    private sealed class RepoFixture : IDisposable
    {
        private readonly DirectoryInfo _root;

        public RepoFixture(DirectoryInfo root)
        {
            _root = root;
            RepoRoot = root.FullName;
        }

        public string RepoRoot { get; }

        public void Dispose()
        {
            try
            {
                if (_root.Exists)
                {
                    _root.Delete(recursive: true);
                }
            }
            catch
            {
                // Best-effort cleanup.
            }
        }
    }

    private sealed class EnvironmentVariableOverride : IDisposable
    {
        private readonly string _name;
        private readonly string? _originalValue;

        public EnvironmentVariableOverride(string name, string? value)
        {
            _name = name;
            _originalValue = Environment.GetEnvironmentVariable(name);
            Environment.SetEnvironmentVariable(name, value);
        }

        public void Dispose()
        {
            Environment.SetEnvironmentVariable(_name, _originalValue);
        }
    }
}
