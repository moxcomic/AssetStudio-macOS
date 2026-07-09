using System.Reflection;
using AssetStudio;

if (args.Length > 0 && args[0] == "--version")
{
    // Read the engine version from the assembly (authoritative: <Version> in the csproj).
    // ToString(3) yields "0.1.0" from the padded 0.1.0.0 AssemblyVersion.
    var engine = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "unknown";
    var core = typeof(AssetsManager).Assembly.GetName().Version?.ToString() ?? "unknown";
    Console.Error.WriteLine($"AssetStudioEngine {engine} (core {core})");
    return 0;
}
Console.Error.WriteLine("AssetStudioEngine: RPC mode arrives in Task 4. Use --version.");
return 1;
