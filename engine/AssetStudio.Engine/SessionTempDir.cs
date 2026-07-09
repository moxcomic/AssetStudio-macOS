namespace AssetStudio.Engine;

public sealed class SessionTempDir : IDisposable
{
    public string Root { get; }

    public SessionTempDir()
    {
        var baseDir = Path.Combine(Path.GetTempPath(), "AssetStudioEngine");
        SweepStale(baseDir);
        Root = Path.Combine(baseDir, Environment.ProcessId.ToString());
        Directory.CreateDirectory(Root);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => Dispose();
    }

    public string PathFor(string fileName) => Path.Combine(Root, fileName);

    public void Clear()
    {
        if (!Directory.Exists(Root)) { Directory.CreateDirectory(Root); return; }
        foreach (var f in Directory.EnumerateFiles(Root)) { try { File.Delete(f); } catch { } }
    }

    private static void SweepStale(string baseDir)
    {
        if (!Directory.Exists(baseDir)) return;
        foreach (var dir in Directory.EnumerateDirectories(baseDir))
        {
            var name = Path.GetFileName(dir);
            if (!int.TryParse(name, out var pid)) continue;
            try { System.Diagnostics.Process.GetProcessById(pid); }
            catch (ArgumentException) { try { Directory.Delete(dir, recursive: true); } catch { } }
        }
    }

    public void Dispose() { try { Directory.Delete(Root, recursive: true); } catch { } }
}
