using AssetStudio;
using Xunit;

namespace AssetStudio.Engine.Tests;

public class SmokeTests
{
    // Proves the vendored core assembly actually links and runs on net10.0/macOS, and pins the
    // exact vendored version so an accidental upstream bump on re-vendor fails loudly here.
    [Fact]
    public void CoreAssemblyLinksAndPinsVersion()
    {
        var manager = new AssetsManager();
        manager.Clear();
        manager.Clear(); // idempotent — a real method call on the core, must not throw

        var coreVersion = typeof(AssetsManager).Assembly.GetName().Version?.ToString();
        Assert.Equal("0.19.0.0", coreVersion);
    }

    // Exercises the core's real Unity-version parser (regex extraction + round-trip), rather
    // than asserting a tautology.
    [Fact]
    public void UnityVersionParsesRealVersionString()
    {
        var version = new UnityVersion("5.6.7f1");

        Assert.Equal(5, version.Major);
        Assert.Equal(6, version.Minor);
        Assert.Equal(7, version.Patch);
        Assert.Equal("5.6.7f1", version.ToString());
    }
}
