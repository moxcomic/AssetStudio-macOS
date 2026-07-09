using AssetStudio;

if (args.Length > 0 && args[0] == "--version")
{
    var core = typeof(AssetsManager).Assembly.GetName().Version?.ToString() ?? "unknown";
    Console.Error.WriteLine($"AssetStudioEngine 0.1.0 (core {core})");
    return 0;
}
Console.Error.WriteLine("AssetStudioEngine: RPC mode arrives in Task 4. Use --version.");
return 1;
