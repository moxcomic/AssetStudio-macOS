using System.Reflection;
using System.Runtime.InteropServices;
using AssetStudio;
using AssetStudio.Engine.Protocol;
using StreamJsonRpc;

namespace AssetStudio.Engine;

public class EngineServer
{
    private readonly Workspace _workspace = new();
    // Single choke point: EVERY workspace operation (load/reset/list/future get/preview/export)
    // acquires this gate, so the non-thread-safe Workspace is never touched concurrently even
    // though StreamJsonRpc dispatches requests concurrently and Load runs on a Task.Run thread.
    private readonly SemaphoreSlim _gate = new(1, 1);
    private JsonRpc? _rpc;

    public Workspace Workspace => _workspace;

    public void Attach(JsonRpc rpc)
    {
        _rpc = rpc;
        _workspace.Progress += (token, current, total) => Notify("progress", new ProgressNote(token, current, total, null));
        Logger.Default = new RpcLogger(note => Notify("log", note));
    }

    private void Notify(string method, object arg)
    {
        try
        {
            var t = _rpc?.NotifyWithParameterObjectAsync(method, arg);
            // Observe async faults (channel closing mid-send) so they don't surface as UnobservedTaskException.
            t?.ContinueWith(static tt => { _ = tt.Exception; },
                CancellationToken.None,
                TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }
        catch { /* channel closing */ }
    }

    [JsonRpcMethod("initialize")]
    public InitializeResult Initialize()
    {
        // Stateless w.r.t. the workspace, so intentionally ungated.
        // Engine version from the assembly (authoritative <Version>), formatted to 3 parts => "0.1.0".
        var engine = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "unknown";
        var core = typeof(AssetsManager).Assembly.GetName().Version?.ToString() ?? "unknown";
        return new InitializeResult(engine, core, new NativeCaps(
            Probe("Texture2DDecoderNative"), Probe("AssetStudioFBXNative"), Probe("fmod")));
    }

    // capabilities.<x> is true precisely when the dylib the core will P/Invoke is loadable.
    private static bool Probe(string lib)
    {
        try
        {
            // 1) Default resolution honoring this assembly's deps.json (covers runtimes/<rid>/native).
            if (NativeLibrary.TryLoad(lib, typeof(EngineServer).Assembly, DllImportSearchPath.AssemblyDirectory, out var h))
            { NativeLibrary.Free(h); return true; }
            // 2) Flat next to the assembly (fmod / FBX are copied here).
            var flat = Path.Combine(AppContext.BaseDirectory, $"lib{lib}.dylib");
            if (File.Exists(flat) && NativeLibrary.TryLoad(flat, out var h2)) { NativeLibrary.Free(h2); return true; }
            // 3) deps.json-standard runtimes path (the vendored texture decoder lives here after the Task-1 fix).
            var rid = Path.Combine(AppContext.BaseDirectory, "runtimes", "osx-arm64", "native", $"lib{lib}.dylib");
            if (File.Exists(rid) && NativeLibrary.TryLoad(rid, out var h3)) { NativeLibrary.Free(h3); return true; }
        }
        catch { }
        return false;
    }

    [JsonRpcMethod("workspace/load")]
    public async Task<LoadResult> LoadAsync(string[] paths, string? unityVersion = null, bool loadAll = false)
    {
        await _gate.WaitAsync();
        try { return await Task.Run(() => _workspace.Load(paths, unityVersion, loadAll)); }
        catch (EngineException e) { throw Wrap(e); }
        catch (Exception e) { throw Wrap(new EngineException(ErrorCodes.LoadFailed, e.Message)); }
        finally { _gate.Release(); }
    }

    [JsonRpcMethod("workspace/reset")]
    public async Task ResetAsync()
    {
        await _gate.WaitAsync();
        try { _workspace.Reset(); }
        catch (EngineException e) { throw Wrap(e); }
        catch (Exception e) { throw Wrap(new EngineException(ErrorCodes.IoError, e.Message)); }
        finally { _gate.Release(); }
    }

    [JsonRpcMethod("assets/list")]
    public async Task<ListResult> ListAsync(int offset, int limit)
    {
        await _gate.WaitAsync();
        try { return _workspace.List(offset, limit); }
        catch (EngineException e) { throw Wrap(e); }
        catch (Exception e) { throw Wrap(new EngineException(ErrorCodes.IoError, e.Message)); }
        finally { _gate.Release(); }
    }

    internal static LocalRpcException Wrap(EngineException e) =>
        new(e.Message) { ErrorCode = -32000, ErrorData = new { code = e.Code } };
}
