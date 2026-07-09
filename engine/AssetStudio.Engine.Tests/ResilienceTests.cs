using Newtonsoft.Json.Linq;
using Xunit;

namespace AssetStudio.Engine.Tests;

public class ResilienceTests
{
    [Fact]
    public void CorruptFileAloneLoadsZeroFilesWithoutCrash()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var r = c.Request("workspace/load",
            new { paths = new[] { Path.Combine(StdioClient.FixturesDir, "corrupt.bin") } });
        Assert.Equal(0, r["loadedFiles"]!.Value<int>());
        Assert.Equal(0, r["assetCount"]!.Value<int>());
        // process still alive and usable:
        Assert.NotNull(c.Request("initialize", null)["engineVersion"]);
    }

    [Fact]
    public void CorruptPlusValidLoadsTheValidOne()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var r = c.Request("workspace/load", new { paths = new[]
        {
            Path.Combine(StdioClient.FixturesDir, "corrupt.bin"),
            Path.Combine(StdioClient.FixturesDir, "char_118_yuki.ab"),
        }});
        Assert.Equal(1, r["loadedFiles"]!.Value<int>());
        Assert.Equal(35, r["assetCount"]!.Value<int>());
    }

    [Fact]
    public void RequestOnEmptyWorkspaceGivesStructuredError()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        var ex = Assert.Throws<InvalidOperationException>(() => c.Request("assets/preview", new { id = 0 }));
        Assert.Contains("BAD_ID", ex.Message);
    }

    [Fact]
    public void UnwritableExportDestGivesStructuredErrorAndSurvives()
    {
        using var c = new StdioClient();
        c.Request("initialize", null);
        c.Request("workspace/load", new { paths = new[] { Path.Combine(StdioClient.FixturesDir, "char_118_yuki.ab") } });
        var ex = Assert.Throws<InvalidOperationException>(() => c.Request("assets/export",
            new { ids = new[] { 0 }, mode = "raw", destDir = "/nonexistent-root-xyz", groupBy = "none", imageFormat = "png" }));
        Assert.Contains("IO_ERROR", ex.Message);
        Assert.NotNull(c.Request("initialize", null)["engineVersion"]);   // engine survived
    }

    [Fact]
    public void CapabilitiesAreStableAcrossCalls()
    {
        using var c = new StdioClient();
        var a = c.Request("initialize", null)["natives"]!;
        var b = c.Request("initialize", null)["natives"]!;
        Assert.Equal(a.ToString(), b.ToString());
    }
}
