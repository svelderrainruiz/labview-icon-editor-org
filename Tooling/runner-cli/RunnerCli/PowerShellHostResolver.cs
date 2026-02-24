namespace RunnerCli;

internal static class PowerShellHostResolver
{
    private static readonly string[] WindowsPreferredHosts =
    {
        "powershell.exe",
        "powershell",
        "pwsh.exe",
        "pwsh"
    };

    private static readonly string[] NonWindowsPreferredHosts =
    {
        "pwsh",
        "pwsh.exe",
        "powershell",
        "powershell.exe"
    };

    public static string ResolveExecutable()
    {
        var candidates = OperatingSystem.IsWindows()
            ? WindowsPreferredHosts
            : NonWindowsPreferredHosts;

        foreach (var candidate in candidates)
        {
            if (TryResolveCommandPath(candidate, out var resolvedPath))
            {
                return resolvedPath;
            }
        }

        throw new InvalidOperationException(
            $"No supported PowerShell host found on PATH. Tried: {string.Join(", ", candidates)}.");
    }

    public static string GetDisplayName(string executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return "powershell";
        }

        return Path.GetFileName(executablePath);
    }

    private static bool TryResolveCommandPath(string command, out string resolvedPath)
    {
        resolvedPath = string.Empty;

        if (string.IsNullOrWhiteSpace(command))
        {
            return false;
        }

        if (Path.IsPathRooted(command) ||
            command.Contains(Path.DirectorySeparatorChar) ||
            command.Contains(Path.AltDirectorySeparatorChar))
        {
            if (!File.Exists(command))
            {
                return false;
            }

            resolvedPath = Path.GetFullPath(command);
            return true;
        }

        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return false;
        }

        var suffixes = GetExecutableSuffixes(command);
        var pathEntries = pathValue.Split(
            Path.PathSeparator,
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        foreach (var pathEntry in pathEntries)
        {
            if (string.IsNullOrWhiteSpace(pathEntry))
            {
                continue;
            }

            foreach (var suffix in suffixes)
            {
                var candidatePath = Path.Combine(pathEntry, command + suffix);
                if (!File.Exists(candidatePath))
                {
                    continue;
                }

                resolvedPath = candidatePath;
                return true;
            }
        }

        return false;
    }

    private static IReadOnlyList<string> GetExecutableSuffixes(string command)
    {
        if (!OperatingSystem.IsWindows())
        {
            return new[] { string.Empty };
        }

        if (Path.HasExtension(command))
        {
            return new[] { string.Empty };
        }

        var pathExtValue = Environment.GetEnvironmentVariable("PATHEXT");
        var rawExtensions = string.IsNullOrWhiteSpace(pathExtValue)
            ? new[] { ".EXE", ".CMD", ".BAT", ".COM" }
            : pathExtValue.Split(
                ';',
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var normalized = rawExtensions
            .Select(ext => ext.StartsWith('.') ? ext : $".{ext}")
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        normalized.Insert(0, string.Empty);
        return normalized;
    }
}
