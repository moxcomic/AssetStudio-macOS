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
        try
        {
            if (!Directory.Exists(baseDir)) return;
            foreach (var dir in Directory.EnumerateDirectories(baseDir))
            {
                try
                {
                    if (!int.TryParse(Path.GetFileName(dir), out var pid)) continue;
                    bool alive;
                    // GetProcessById returns a handle that must be disposed when the process exists;
                    // it throws ArgumentException when no such process is running.
                    try { using var proc = System.Diagnostics.Process.GetProcessById(pid); alive = true; }
                    catch (ArgumentException) { alive = false; }
                    if (!alive) Directory.Delete(dir, recursive: true);
                }
                catch { /* one bad dir must not stop sweeping the rest */ }
            }
        }
        catch { /* temp housekeeping must never abort engine startup */ }
    }

    public void Dispose() { try { Directory.Delete(Root, recursive: true); } catch { } }
}
