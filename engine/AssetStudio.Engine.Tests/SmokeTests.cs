using AssetStudio;
using Xunit;

namespace AssetStudio.Engine.Tests;

public class SmokeTests
{
    [Fact]
    public void CoreAssembliesLoadOnMacOS()
    {
        var manager = new AssetsManager();
        Assert.NotNull(manager);
        Assert.True(OperatingSystem.IsMacOS());
    }
}
