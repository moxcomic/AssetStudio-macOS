using Newtonsoft.Json.Linq;
using Xunit;

namespace AssetStudio.Engine.Tests;

public class LoadListTests
{
    [Fact]
    public void InitializeReportsNativeCapabilities()
    {
        using var c = new StdioClient();
        var r = c.Request("initialize", null);
        Assert.Equal("0.1.0", r["engineVersion"]!.Value<string>());
        Assert.True(r["natives"]!["texture"]!.Value<bool>());
        Assert.True(r["natives"]!["fbx"]!.Value<bool>());
        Assert.True(r["natives"]!["fmod"]!.Value<bool>());
    }

    [Fact]
    public void LoadsKnownBundleAndListsAssets()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var load = c.Request("workspace/load",
            new { paths = new[] { Path.Combine(StdioClient.FixturesDir, "char_118_yuki.ab") } });
        Assert.Equal(1, load["loadedFiles"]!.Value<int>());
        Assert.Equal(35, load["assetCount"]!.Value<int>());
        Assert.Equal("5.6.7f1", load["unityVersion"]!.Value<string>());

        var list = c.Request("assets/list", new { offset = 0, limit = 5000 });
        Assert.Equal(35, list["total"]!.Value<int>());
        var rows = (JArray)list["rows"]!;
        Assert.Equal(35, rows.Count);
        Assert.All(rows, r => Assert.Equal("AudioClip", r["type"]!.Value<string>()));
        Assert.All(rows, r => Assert.False(string.IsNullOrEmpty(r["name"]!.Value<string>())));
        Assert.Contains(c.Notifications, n => n["method"]!.Value<string>() == "progress");
    }

    [Fact]
    public void ListPaginates()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        c.Request("workspace/load",
            new { paths = new[] { Path.Combine(StdioClient.FixturesDir, "char_118_yuki.ab") } });
        var page = c.Request("assets/list", new { offset = 30, limit = 10 });
        Assert.Equal(35, page["total"]!.Value<int>());
        Assert.Equal(5, ((JArray)page["rows"]!).Count);
        Assert.Equal(30, page["rows"]![0]!["id"]!.Value<int>());
    }

    [Fact]
    public void MissingPathFailsWithInvalidPaths()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var ex = Assert.Throws<InvalidOperationException>(() =>
            c.Request("workspace/load", new { paths = new[] { "/nonexistent/nope.ab" } }));
        Assert.Contains("INVALID_PATHS", ex.Message);
    }

    [Fact]
    public void LoadErrorUsesStructuredCodeEnvelope()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var msg = c.RequestFull("workspace/load", new { paths = new[] { "/nonexistent/nope.ab" } });
        var err = (JObject)msg["error"]!;
        Assert.Equal(-32000, err["code"]!.Value<int>());
        Assert.Equal("INVALID_PATHS", err["data"]!["code"]!.Value<string>());
    }

    [Fact]
    public void ResetClearsWorkspace()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        c.Request("workspace/load",
            new { paths = new[] { Path.Combine(StdioClient.FixturesDir, "char_118_yuki.ab") } });
        c.Request("workspace/reset", null);
        var list = c.Request("assets/list", new { offset = 0, limit = 5000 });
        Assert.Equal(0, list["total"]!.Value<int>());
        Assert.Empty((JArray)list["rows"]!);
    }

    [Fact]
    public void SecondLoadReplacesNotAccumulates()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var path = Path.Combine(StdioClient.FixturesDir, "char_118_yuki.ab");
        c.Request("workspace/load", new { paths = new[] { path } });
        var load2 = c.Request("workspace/load", new { paths = new[] { path } });
        Assert.Equal(35, load2["assetCount"]!.Value<int>());
        var list = c.Request("assets/list", new { offset = 0, limit = 5000 });
        Assert.Equal(35, list["total"]!.Value<int>());
    }
}
