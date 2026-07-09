using Newtonsoft.Json.Linq;
using SixLabors.ImageSharp;
using Xunit;

namespace AssetStudio.Engine.Tests;

public class PreviewTests
{
    private static StdioClient LoadFixture(string name, bool loadAll = false)
    {
        var c = new StdioClient();
        c.Request("initialize", null);
        c.Request("workspace/load",
            new { paths = new[] { Path.Combine(StdioClient.FixturesDir, name) }, loadAll });
        return c;
    }

    private static JArray Rows(StdioClient c) =>
        (JArray)c.Request("assets/list", new { offset = 0, limit = 100000 })["rows"]!;

    [Fact]
    public void Texture2DPreviewProducesDecodablePng()
    {
        using var c = LoadFixture("xinzexi_2_n_tex");
        var tex = Rows(c).FirstOrDefault(r => r["type"]!.Value<string>() == "Texture2D");
        Assert.NotNull(tex);
        var p = c.Request("assets/preview", new { id = tex!["id"]!.Value<int>() });
        Assert.Equal("image", p["kind"]!.Value<string>());
        var path = p["path"]!.Value<string>()!;
        Assert.True(File.Exists(path));
        using var img = Image.Load(path);
        Assert.True(img.Width > 0 && img.Height > 0);
        Assert.Equal(img.Width.ToString(), p["meta"]!["extra"]!["Width"]!.Value<string>());
    }

    [Fact]
    public void SpritePreviewWorksWhenPresent()
    {
        using var c = LoadFixture("atlas_test");
        var sprite = Rows(c).FirstOrDefault(r => r["type"]!.Value<string>() == "Sprite");
        Assert.NotNull(sprite); // atlas_test contains 7 Sprites per fixtures/README.md — a miss means a real parse problem
        var p = c.Request("assets/preview", new { id = sprite!["id"]!.Value<int>() });
        Assert.Equal("image", p["kind"]!.Value<string>());
        Assert.True(File.Exists(p["path"]!.Value<string>()!));
    }

    [Fact]
    public void AudioClipPreviewIsNoneWithMeta()
    {
        using var c = LoadFixture("char_118_yuki.ab");
        var p = c.Request("assets/preview", new { id = 0 });
        Assert.Equal("none", p["kind"]!.Value<string>());
        Assert.Equal("AudioClip", p["meta"]!["type"]!.Value<string>());
        Assert.NotEmpty(((JObject)p["meta"]!["extra"]!).Properties());
    }

    [Fact]
    public void PreviewIsCachedSecondCallSamePath()
    {
        using var c = LoadFixture("xinzexi_2_n_tex");
        var tex = Rows(c).First(r => r["type"]!.Value<string>() == "Texture2D");
        var id = tex["id"]!.Value<int>();
        var p1 = c.Request("assets/preview", new { id });
        var p2 = c.Request("assets/preview", new { id });
        Assert.Equal(p1["path"]!.Value<string>(), p2["path"]!.Value<string>());
    }

    [Fact]
    public void BadIdFails()
    {
        using var c = LoadFixture("char_118_yuki.ab");
        var ex = Assert.Throws<InvalidOperationException>(() => c.Request("assets/preview", new { id = 99999 }));
        Assert.Contains("BAD_ID", ex.Message);
    }

    [Fact]
    public void PreviewCacheHitDoesNotRecompute()
    {
        using var c = LoadFixture("xinzexi_2_n_tex");
        var id = Rows(c).First(r => r["type"]!.Value<string>() == "Texture2D")["id"]!.Value<int>();
        var path = c.Request("assets/preview", new { id })["path"]!.Value<string>()!;
        Assert.True(File.Exists(path));
        File.WriteAllText(path, "SENTINEL"); // clobber the PNG; a recompute would overwrite this
        var again = c.Request("assets/preview", new { id })["path"]!.Value<string>()!;
        Assert.Equal(path, again);
        Assert.Equal("SENTINEL", File.ReadAllText(again)); // cache hit => Build not called => sentinel survives
    }

    [Fact]
    public void ResetInvalidatesPreviewCacheAndDeletesTempFiles()
    {
        using var c = LoadFixture("xinzexi_2_n_tex");
        var id = Rows(c).First(r => r["type"]!.Value<string>() == "Texture2D")["id"]!.Value<int>();
        var path = c.Request("assets/preview", new { id })["path"]!.Value<string>()!;
        Assert.True(File.Exists(path));
        c.Request("workspace/reset", null);
        Assert.False(File.Exists(path)); // InvalidateAll cleared the temp dir
    }

    [Fact]
    public void LoadAllExposesTextDumpForNonMediaAsset()
    {
        using var c = LoadFixture("atlas_test", loadAll: true);
        var atlas = Rows(c).FirstOrDefault(r => r["type"]!.Value<string>() == "SpriteAtlas");
        Assert.NotNull(atlas); // loadAll surfaces the SpriteAtlas -> default case -> DumpAsset
        var p = c.Request("assets/preview", new { id = atlas!["id"]!.Value<int>() });
        Assert.Equal("text", p["kind"]!.Value<string>());
        var text = p["text"]!.Value<string>();
        var path = p["path"]!.Value<string>();
        Assert.True(!string.IsNullOrEmpty(text) || !string.IsNullOrEmpty(path));
    }
}
