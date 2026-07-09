// Adapted from vendored AssetStudioCLI/Components/AssetItem.cs (MIT, aelurum/AssetStudio).
using AssetStudio;
// Disambiguate: with ImplicitUsings, unqualified `Object` is ambiguous between System.Object
// and AssetStudio.Object. The vendored CLI avoids this by not importing System; we alias instead.
using Object = AssetStudio.Object;

namespace AssetStudio.Engine;

public class EngineAssetItem
{
    public int Id;
    public Object Asset;
    public SerializedFile SourceFile;
    public string Container = string.Empty;
    public string TypeString;
    public long PathId;
    public long FullSize;
    public ClassIDType Type;
    public string Text = string.Empty;
    public string UniqueId = string.Empty;

    public EngineAssetItem(Object asset)
    {
        Asset = asset;
        SourceFile = asset.assetsFile;
        Type = asset.type;
        TypeString = Type.ToString();
        PathId = asset.m_PathID;
        FullSize = asset.byteSize;
    }
}
