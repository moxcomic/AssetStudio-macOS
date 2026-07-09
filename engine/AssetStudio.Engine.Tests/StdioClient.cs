using System.Diagnostics;
using System.Text;
using Newtonsoft.Json.Linq;
using Xunit;

namespace AssetStudio.Engine.Tests;

public sealed class StdioClient : IDisposable
{
    private readonly Process _proc;
    private int _nextId = 1;

    // NOTE: points at the Release output. These integration tests require the engine to have been
    // built with `-c Release` first (a plain Debug `dotnet test` will fail the File.Exists assert).
    // `dotnet test -c Release` builds it as a project dependency; CI/local both run in Release.
    public static string EngineBinary =>
        Environment.GetEnvironmentVariable("ENGINE_BIN")
        ?? Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
            "..", "..", "..", "..", "AssetStudio.Engine", "bin", "Release", "net10.0", "AssetStudioEngine"));

    public static string FixturesDir =>
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "fixtures"));

    public List<JObject> Notifications { get; } = new();

    public StdioClient()
    {
        Assert.True(File.Exists(EngineBinary), $"engine binary not found at {EngineBinary} — build AssetStudio.Engine -c Release first");
        _proc = Process.Start(new ProcessStartInfo(EngineBinary)
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;
    }

    // Throws on an RPC error (message = the error object), returns the result token on success.
    public JToken Request(string method, object? @params, int timeoutSec = 60)
    {
        var msg = RequestFull(method, @params, timeoutSec);
        if (msg["error"] is JObject err) throw new InvalidOperationException(err.ToString());
        return msg["result"]!;
    }

    // Returns the full response message (carrying "result" OR "error"); does not throw on RPC error,
    // so callers can assert the structured error envelope (error.code / error.data.code).
    public JObject RequestFull(string method, object? @params, int timeoutSec = 60)
    {
        var id = _nextId++;
        Send(new JObject
        {
            ["jsonrpc"] = "2.0", ["id"] = id, ["method"] = method,
            ["params"] = @params == null ? new JObject() : JObject.FromObject(@params),
        });
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSec);
        while (DateTime.UtcNow < deadline)
        {
            var msg = ReadMessage(deadline);
            if (msg["id"]?.Value<int?>() == id) return msg;
            if (msg["method"] != null) Notifications.Add(msg);
        }
        throw new TimeoutException($"no response to {method}");
    }

    private void Send(JObject obj)
    {
        var body = Encoding.UTF8.GetBytes(obj.ToString(Newtonsoft.Json.Formatting.None));
        var header = Encoding.ASCII.GetBytes($"Content-Length: {body.Length}\r\n\r\n");
        var s = _proc.StandardInput.BaseStream;
        s.Write(header); s.Write(body); s.Flush();
    }

    // Bounded read: the blocking frame read runs on a background task and is capped by the deadline.
    // A hung engine can no longer hang the test forever — on timeout we kill the child and throw.
    // Sync waits (Wait/Result) are intentional in this blocking test client; the frame read runs on a
    // threadpool task with no captured SynchronizationContext, so there is no sync-over-async deadlock.
#pragma warning disable VSTHRD002 // Avoid problematic synchronous waits — intentional here
    private JObject ReadMessage(DateTime deadline)
    {
        var readTask = Task.Run(ReadFrameBlocking);
        var remaining = deadline - DateTime.UtcNow;
        if (remaining < TimeSpan.Zero) remaining = TimeSpan.Zero;

        bool completed;
        try { completed = readTask.Wait(remaining); }
        catch (AggregateException ae) { throw ae.InnerException ?? ae; } // read faulted (e.g., engine closed stdout)

        if (!completed)
        {
            try { if (!_proc.HasExited) _proc.Kill(entireProcessTree: true); } catch { }
            _ = readTask.ContinueWith(static t => { _ = t.Exception; },
                CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default); // observe abandoned read
            throw new TimeoutException("engine read timed out");
        }
        return readTask.Result;
    }
#pragma warning restore VSTHRD002

    private JObject ReadFrameBlocking()
    {
        var s = _proc.StandardOutput.BaseStream;
        var headerBuf = new StringBuilder();
        while (!headerBuf.ToString().EndsWith("\r\n\r\n"))
        {
            var b = s.ReadByte();
            if (b < 0) throw new EndOfStreamException("engine closed stdout");
            headerBuf.Append((char)b);
        }
        var lenLine = headerBuf.ToString().Split("\r\n")
            .First(l => l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase));
        var len = int.Parse(lenLine.Split(':')[1].Trim());
        var body = new byte[len];
        var read = 0;
        while (read < len)
        {
            var n = s.Read(body, read, len - read);
            if (n <= 0) throw new EndOfStreamException("engine closed stdout mid-body");
            read += n;
        }
        return JObject.Parse(Encoding.UTF8.GetString(body));
    }

    public void Dispose()
    {
        try { if (!_proc.HasExited) _proc.Kill(entireProcessTree: true); } catch { }
        _proc.Dispose();
    }
}
