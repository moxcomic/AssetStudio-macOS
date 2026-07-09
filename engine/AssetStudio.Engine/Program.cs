using System.Reflection;
using AssetStudio;
using AssetStudio.Engine;
using Newtonsoft.Json.Serialization;
using StreamJsonRpc;

if (args.Length > 0 && args[0] == "--version")
{
    // Read the engine version from the assembly (authoritative: <Version> in the csproj).
    // ToString(3) yields "0.1.0" from the padded 0.1.0.0 AssemblyVersion.
    var engineVer = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "unknown";
    var coreVer = typeof(AssetsManager).Assembly.GetName().Version?.ToString() ?? "unknown";
    Console.Error.WriteLine($"AssetStudioEngine {engineVer} (core {coreVer})");
    return 0;
}

var formatter = new JsonMessageFormatter();
// camelCase properties but NOT dictionary keys (later previews carry meta.extra keys like "Width" that must survive)
formatter.JsonSerializer.ContractResolver = new DefaultContractResolver
{
    NamingStrategy = new CamelCaseNamingStrategy { ProcessDictionaryKeys = false, OverrideSpecifiedNames = true },
};
var handler = new HeaderDelimitedMessageHandler(
    Console.OpenStandardOutput(), Console.OpenStandardInput(), formatter);

var server = new EngineServer();
var rpc = new JsonRpc(handler);
rpc.AddLocalRpcTarget(server, null);
server.Attach(rpc);
rpc.StartListening();
Console.Error.WriteLine("AssetStudioEngine listening on stdio");
// rpc.Completion is this server's own connection lifetime; awaiting it IS the main loop (VSTHRD003 false positive).
#pragma warning disable VSTHRD003
await rpc.Completion;
#pragma warning restore VSTHRD003
return 0;
