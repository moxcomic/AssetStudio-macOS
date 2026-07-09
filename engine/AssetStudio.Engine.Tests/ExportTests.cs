using Newtonsoft.Json.Linq;
using SixLabors.ImageSharp;
using Xunit;

namespace AssetStudio.Engine.Tests;

public class ExportTests
{
    private static (StdioClient c, string dest) Prep(string fixture)
    {
        var c = new StdioClient();
        c.Request("initialize", null);
        c.Request("workspace/load", new { paths = new[] { Path.Combine(StdioClient.FixturesDir, fixture) } });
        var dest = Path.Combine(Path.GetTempPath(), "ase-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dest);
        return (c, dest);
    }

    [Fact]
    public void ConvertExportsTexturesAsPng()
    {
        var (c, dest) = Prep("xinzexi_2_n_tex");
        using var _ = c;
        var ids = ((JArray)c.Request("assets/list", new { offset = 0, limit = 100000 })["rows"]!)
            .Where(r => r["type"]!.Value<string>() == "Texture2D")
            .Select(r => r["id"]!.Value<int>()).ToArray();
        Assert.NotEmpty(ids);
        var r = c.Request("assets/export",
            new { ids, mode = "convert", destDir = dest, groupBy = "typeName", imageFormat = "png" }, 300);
        Assert.Equal(ids.Length, r["exported"]!.Value<int>());
        var files = Directory.GetFiles(Path.Combine(dest, "Texture2D"), "*.png");
        Assert.Equal(ids.Length, files.Length);
        Assert.Contains(c.Notifications, n => n["method"]!.Value<string>() == "progress"
            && n["params"]!["token"]!.Value<string>() == "export");
    }

    [Fact]
    public void RawAndDumpExportAudio()
    {
        var (c, dest) = Prep("char_118_yuki.ab");
        using var _ = c;
        var raw = c.Request("assets/export",
            new { ids = new[] { 0, 1 }, mode = "raw", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        Assert.Equal(2, raw["exported"]!.Value<int>());
        Assert.Equal(2, Directory.GetFiles(dest, "*.dat").Length);

        var dump = c.Request("assets/export",
            new { ids = new[] { 0 }, mode = "dump", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        Assert.Equal(1, dump["exported"]!.Value<int>());
        Assert.Single(Directory.GetFiles(dest, "*.txt"));
    }

    [Fact]
    public void ConvertAudioProducesWavOrOriginalFormat()
    {
        var (c, dest) = Prep("char_118_yuki.ab");
        using var _ = c;
        var r = c.Request("assets/export",
            new { ids = new[] { 0 }, mode = "convert", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        Assert.Equal(1, r["exported"]!.Value<int>() + r["skipped"]!.Value<int>());
        Assert.True(Directory.GetFiles(dest).Length >= r["exported"]!.Value<int>());
    }

    [Fact]
    public void AllTypesConvertWithoutUnportedExporters()
    {
        // Forces the ported exporters to be real: any NotImplementedException surfaces per-asset.
        // NOTE: fixtures/xinzexi_2_n_tex_mesh is a golden Wavefront OBJ reference — NOT a bundle —
        // and must NOT be loaded. Load the real bundles; the grep guard in Step 5 is the hard
        // enforcement that all five bodies were ported.
        using var c = new StdioClient();
        c.Request("initialize", null);
        c.Request("workspace/load", new { paths = new[]
        {
            Path.Combine(StdioClient.FixturesDir, "xinzexi_2_n_tex"),
            Path.Combine(StdioClient.FixturesDir, "atlas_test"),
            Path.Combine(StdioClient.FixturesDir, "banner_1"),
        }});
        var dest = Path.Combine(Path.GetTempPath(), "ase-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dest);
        var ids = ((JArray)c.Request("assets/list", new { offset = 0, limit = 100000 })["rows"]!)
            .Select(r => r["id"]!.Value<int>()).ToArray();
        Assert.NotEmpty(ids);
        var r = c.Request("assets/export",
            new { ids, mode = "convert", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        var errors = (JArray)r["errors"]!;
        Assert.DoesNotContain(errors, e => e["message"]!.Value<string>()!.Contains("port from vendored"));
        Assert.DoesNotContain(errors, e => e["message"]!.Value<string>()!.Contains("NotImplemented"));
    }

    [Fact]
    public void GroupByContainerPathCreatesDirectories()
    {
        var (c, dest) = Prep("char_118_yuki.ab");
        using var _ = c;
        c.Request("assets/export",
            new { ids = new[] { 0, 1, 2 }, mode = "raw", destDir = dest, groupBy = "containerPath", imageFormat = "png" }, 300);
        Assert.True(Directory.Exists(dest));
        Assert.True(Directory.GetFiles(dest, "*", SearchOption.AllDirectories).Length >= 3);
    }

    [Fact]
    public void ReExportOverwritesWithoutCorruption()
    {
        var (c, dest) = Prep("xinzexi_2_n_tex");
        using var _ = c;
        var id = ((JArray)c.Request("assets/list", new { offset = 0, limit = 100000 })["rows"]!)
            .First(r => r["type"]!.Value<string>() == "Texture2D")["id"]!.Value<int>();
        c.Request("assets/export",
            new { ids = new[] { id }, mode = "convert", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        var png = Directory.GetFiles(dest, "*.png").Single();
        var goodLen = new FileInfo(png).Length;
        // Simulate a previous, larger export at the same name by appending trailing garbage.
        using (var fs = new FileStream(png, FileMode.Append)) fs.Write(new byte[(int)goodLen]);
        Assert.True(new FileInfo(png).Length > goodLen);
        // Re-export: File.Create must truncate, not leave a stale tail (File.OpenWrite would corrupt).
        c.Request("assets/export",
            new { ids = new[] { id }, mode = "convert", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        Assert.Equal(goodLen, new FileInfo(png).Length);
        using var img = Image.Load(png); // decodes cleanly — no trailing garbage
        Assert.True(img.Width > 0);
    }

    [Fact]
    public void BadIdBecomesPerAssetErrorNotBatchAbort()
    {
        var (c, dest) = Prep("char_118_yuki.ab");
        using var _ = c;
        var r = c.Request("assets/export",
            new { ids = new[] { 0, 999999 }, mode = "raw", destDir = dest, groupBy = "none", imageFormat = "png" }, 300);
        Assert.Equal(1, r["exported"]!.Value<int>()); // id 0 still exported despite the bad id
        var errors = (JArray)r["errors"]!;
        Assert.Contains(errors, e => e["id"]!.Value<int>() == 999999); // bad id → per-asset error entry
    }

    [Fact]
    public void ExportRespectsPreCanceledToken()
    {
        var dest = Path.Combine(Path.GetTempPath(), "ase-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dest);
        var svc = new ExportService(new Workspace(), new AssemblyLoader());
        var opts = new ExportRequestOptions("raw", dest, "none", "png");
        Assert.ThrowsAny<OperationCanceledException>(() =>
            svc.Export(new[] { 0 }, opts, new CancellationToken(canceled: true)));
    }
}
