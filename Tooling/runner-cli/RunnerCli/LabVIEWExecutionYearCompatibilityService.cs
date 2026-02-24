namespace RunnerCli;

public sealed record LabVIEWExecutionYearResolution(
    LabVIEWVersionInfo SourceVersion,
    string ExecutionYear,
    bool CompatMappingApplied
);

public static class LabVIEWExecutionYearCompatibilityService
{
    public const string SourceYearLv2020 = "2020";
    public const string FallbackExecutionYear = "2026";
    public const string ExecutionYearOverrideEnvVar = "LVIE_RUNNERCLI_EXECUTION_LABVIEW_YEAR";

    public static LabVIEWExecutionYearResolution Resolve(
        string? sourceLabviewVersion,
        string repoRoot,
        string commandLabel)
    {
        if (string.IsNullOrWhiteSpace(repoRoot))
        {
            throw new ArgumentException("Repo root is required.", nameof(repoRoot));
        }

        var sourceVersion = LabVIEWVersionService.GetVersionInfo(sourceLabviewVersion, repoRoot);
        var executionYearOverride = Environment.GetEnvironmentVariable(ExecutionYearOverrideEnvVar)?.Trim();
        var hasExecutionYearOverride = !string.IsNullOrWhiteSpace(executionYearOverride);
        if (hasExecutionYearOverride &&
            !System.Text.RegularExpressions.Regex.IsMatch(executionYearOverride!, @"^\d{4}$"))
        {
            throw new InvalidOperationException(
                $"{ExecutionYearOverrideEnvVar} must be a 4-digit year. actual='{executionYearOverride}'.");
        }

        var compatMappingApplied = false;
        var executionYear = sourceVersion.Year;
        if (hasExecutionYearOverride)
        {
            executionYear = executionYearOverride!;
            compatMappingApplied = !string.Equals(
                sourceVersion.Year,
                executionYear,
                StringComparison.Ordinal);
        }
        else
        {
            compatMappingApplied = string.Equals(
                sourceVersion.Year,
                SourceYearLv2020,
                StringComparison.Ordinal);
            executionYear = compatMappingApplied ? FallbackExecutionYear : sourceVersion.Year;
        }

        Console.Error.WriteLine(
            $"{commandLabel} LabVIEW source contract: raw={sourceVersion.Raw}; year={sourceVersion.Year}; minor={sourceVersion.MinorRevision}.");
        if (hasExecutionYearOverride)
        {
            Console.Error.WriteLine(
                $"{commandLabel} LabVIEW execution-year override applied via {ExecutionYearOverrideEnvVar}: source year {sourceVersion.Year} -> execution year {executionYear}.");
        }
        else if (compatMappingApplied)
        {
            Console.Error.WriteLine(
                $"{commandLabel} LabVIEW execution-year compatibility mapping applied: source year {sourceVersion.Year} -> execution year {executionYear}.");
        }
        else
        {
            Console.Error.WriteLine(
                $"{commandLabel} LabVIEW execution year: {executionYear} (compatibility mapping not applied).");
        }

        return new LabVIEWExecutionYearResolution(
            SourceVersion: sourceVersion,
            ExecutionYear: executionYear,
            CompatMappingApplied: compatMappingApplied);
    }
}
