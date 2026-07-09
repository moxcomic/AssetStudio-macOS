using System.Diagnostics;
using System.Text;
using Newtonsoft.Json.Linq;
using Xunit;

namespace AssetStudio.Engine.Tests;

public sealed class StdioClient : IDisposable
{
    private readonly Process _proc;
    private int _nextId = 1;

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

    public JToken Request(string method, object? @params, int timeoutSec = 60)
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
            if (msg["id"]?.Value<int?>() == id)
            {
                if (msg["error"] is JObject err) throw new InvalidOperationException(err.ToString());
                return msg["result"]!;
            }
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

    private JObject ReadMessage(DateTime deadline)
    {
        var s = _proc.StandardOutput.BaseStream;
        var headerBuf = new StringBuilder();
        while (!headerBuf.ToString().EndsWith("\r\n\r\n"))
        {
            var b = s.ReadByte();
            if (b < 0) throw new EndOfStreamException("engine closed stdout");
            headerBuf.Append((char)b);
            if (DateTime.UtcNow > deadline) throw new TimeoutException("header read");
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
