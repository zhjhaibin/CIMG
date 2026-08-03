using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class CimgLauncher
{
    private static int Main(string[] args)
    {
        string launcherDirectory = Path.GetDirectoryName(typeof(CimgLauncher).Assembly.Location);
        string compressor = Path.Combine(launcherDirectory, "Compress-Photos.ps1");
        string currentDirectory = Environment.CurrentDirectory;

        if (!File.Exists(compressor))
        {
            Console.Error.WriteLine("Compressor script not found: " + compressor);
            return 1;
        }

        var forwardedArguments = new List<string>();
        forwardedArguments.Add("-NoLogo");
        forwardedArguments.Add("-NoProfile");
        forwardedArguments.Add("-ExecutionPolicy");
        forwardedArguments.Add("Bypass");
        forwardedArguments.Add("-File");
        forwardedArguments.Add(compressor);

        if (args.Length == 0 || args[0].StartsWith("-", StringComparison.Ordinal))
        {
            forwardedArguments.Add(currentDirectory);
        }

        if (args.Length > 0)
        {
            foreach (string argument in args)
            {
                forwardedArguments.Add(ResolveRelativeDotPath(argument, currentDirectory));
            }
        }

        var startInfo = new ProcessStartInfo();
        startInfo.FileName = "powershell.exe";
        startInfo.Arguments = JoinArguments(forwardedArguments);
        startInfo.UseShellExecute = false;
        startInfo.WorkingDirectory = launcherDirectory;

        try
        {
            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    private static string ResolveRelativeDotPath(string argument, string currentDirectory)
    {
        if (argument == "." || argument == ".\\" || argument == "./")
        {
            return currentDirectory;
        }

        if (argument.StartsWith(".\\", StringComparison.Ordinal) ||
            argument.StartsWith("./", StringComparison.Ordinal) ||
            argument == ".." ||
            argument.StartsWith("..\\", StringComparison.Ordinal) ||
            argument.StartsWith("../", StringComparison.Ordinal))
        {
            return Path.GetFullPath(Path.Combine(currentDirectory, argument));
        }

        return argument;
    }

    private static string JoinArguments(IEnumerable<string> arguments)
    {
        var commandLine = new StringBuilder();
        foreach (string argument in arguments)
        {
            if (commandLine.Length > 0)
            {
                commandLine.Append(' ');
            }
            commandLine.Append(QuoteArgument(argument));
        }
        return commandLine.ToString();
    }

    private static string QuoteArgument(string argument)
    {
        if (argument.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = false;
        foreach (char character in argument)
        {
            if (char.IsWhiteSpace(character) || character == '"')
            {
                needsQuotes = true;
                break;
            }
        }

        if (!needsQuotes)
        {
            return argument;
        }

        var quoted = new StringBuilder();
        quoted.Append('"');
        int backslashCount = 0;

        foreach (char character in argument)
        {
            if (character == '\\')
            {
                backslashCount++;
                continue;
            }

            if (character == '"')
            {
                quoted.Append('\\', (backslashCount * 2) + 1);
                quoted.Append('"');
                backslashCount = 0;
                continue;
            }

            quoted.Append('\\', backslashCount);
            backslashCount = 0;
            quoted.Append(character);
        }

        quoted.Append('\\', backslashCount * 2);
        quoted.Append('"');
        return quoted.ToString();
    }
}
