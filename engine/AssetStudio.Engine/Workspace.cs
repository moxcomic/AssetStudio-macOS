using AssetStudio;
using AssetStudio.Engine.Protocol;
// With ImplicitUsings, unqualified `Object` is ambiguous (System.Object vs AssetStudio.Object).
using Object = AssetStudio.Object;

namespace AssetStudio.Engine;

public class Workspace
{
    private static readonly HashSet<ClassIDType> ExportableTypes = new()
    {
        ClassIDType.Texture2D, ClassIDType.Texture2DArray, ClassIDType.Sprite,
        ClassIDType.TextAsset, ClassIDType.MonoBehaviour, ClassIDType.Font,
        ClassIDType.Shader, ClassIDType.AudioClip, ClassIDType.VideoClip,
        ClassIDType.MovieTexture, ClassIDType.Mesh, ClassIDType.Animator,
    };

    public readonly AssetsManager Manager = new();
    public readonly List<EngineAssetItem> Assets = new();
    private AssetRowDto[]? _rowCache;

    public event Action<string, int, int>? Progress; // token, current, total

    public LoadResult Load(string[] paths, string? unityVersion, bool loadAll)
    {
        var missing = paths.Where(p => !File.Exists(p) && !Directory.Exists(p)).ToList();
        if (missing.Count > 0)
            throw new EngineException(ErrorCodes.InvalidPaths, $"paths do not exist: {string.Join(", ", missing)}");

        Reset();
        if (!string.IsNullOrEmpty(unityVersion))
        {
            // The vendored CLI applies --unity-version via assetsManager.Options.CustomUnityVersion
            // (AssetStudioCLI/Studio.cs:35; consumed at AssetStudio/AssetsManager.cs:599-601).
            Manager.Options.CustomUnityVersion = new UnityVersion(unityVersion);
        }
        try
        {
            Manager.LoadFilesAndFolders(out _, paths.ToList());
        }
        catch (Exception e)
        {
            throw new EngineException(ErrorCodes.LoadFailed, $"load failed: {e.Message}");
        }
        ParseAssets(loadAll);
        var version = Manager.AssetsFileList.Count > 0 ? Manager.AssetsFileList[0].version.ToString() : null;
        return new LoadResult(Manager.AssetsFileList.Count, Assets.Count, version);
    }

    public void Reset()
    {
        Manager.Clear();
        Assets.Clear();
        _rowCache = null;
    }

    public ListResult List(int offset, int limit)
    {
        _rowCache ??= Assets.Select(a => new AssetRowDto(
            a.Id, a.Text, a.Container, a.TypeString, a.PathId, a.FullSize, a.SourceFile.fileName)).ToArray();
        var slice = _rowCache.Skip(Math.Max(0, offset)).Take(Math.Clamp(limit, 0, 100_000)).ToList();
        return new ListResult(_rowCache.Length, slice);
    }

    public EngineAssetItem Get(int id)
    {
        if (id < 0 || id >= Assets.Count)
            throw new EngineException(ErrorCodes.BadId, $"no asset with id {id}");
        return Assets[id];
    }

    // Faithful adaptation of vendored ParseAssets (AssetStudioCLI/Studio.cs ~198-397): containers via
    // the AssetBundle preload table / ResourceManager, display text per type, Texture2DArray layer
    // expansion, exportable filter. CLIOptions and all Live2D/Cubism bookkeeping are dropped.
    private void ParseAssets(bool loadAll)
    {
        var objectCount = Manager.AssetsFileList.Sum(x => x.Objects.Count);
        var i = 0;
        var lastPercent = -1;
        foreach (var assetsFile in Manager.AssetsFileList)
        {
            var containers = new Dictionary<Object, string>();
            var fileAssets = new List<EngineAssetItem>();
            var tex2dArrays = new List<EngineAssetItem>();
            var preloadTable = new List<PPtr<Object>>();

            foreach (var asset in assetsFile.Objects)
            {
                var item = new EngineAssetItem(asset) { UniqueId = "_#" + i };
                var include = loadAll || ExportableTypes.Contains(asset.type);
                switch (asset)
                {
                    case PreloadData m_PreloadData:
                        preloadTable = m_PreloadData.m_Assets;
                        break;
                    case AssetBundle m_AssetBundle:
                        var streamed = m_AssetBundle.m_IsStreamedSceneAssetBundle;
                        if (!streamed) preloadTable = m_AssetBundle.m_PreloadTable;
                        item.Text = string.IsNullOrEmpty(m_AssetBundle.m_AssetBundleName)
                            ? m_AssetBundle.m_Name : m_AssetBundle.m_AssetBundleName;
                        foreach (var m_Container in m_AssetBundle.m_Container)
                        {
                            var preloadIndex = m_Container.Value.preloadIndex;
                            var preloadSize = streamed ? preloadTable.Count : m_Container.Value.preloadSize;
                            for (var k = preloadIndex; k < preloadIndex + preloadSize; k++)
                            {
                                if (k >= preloadTable.Count) break;
                                if (preloadTable[k].TryGet(out var obj)) containers[obj] = m_Container.Key;
                            }
                        }
                        break;
                    case ResourceManager m_ResourceManager:
                        foreach (var m_Container in m_ResourceManager.m_Container)
                            if (m_Container.Value.TryGet(out var obj)) containers[obj] = m_Container.Key;
                        break;
                    case Texture2D m_Texture2D:
                        if (!string.IsNullOrEmpty(m_Texture2D.m_StreamData?.path))
                            item.FullSize = asset.byteSize + m_Texture2D.m_StreamData.size;
                        item.Text = m_Texture2D.m_Name;
                        break;
                    case Texture2DArray m_Texture2DArray:
                        if (!string.IsNullOrEmpty(m_Texture2DArray.m_StreamData?.path))
                            item.FullSize = asset.byteSize + m_Texture2DArray.m_StreamData.size;
                        item.Text = m_Texture2DArray.m_Name;
                        tex2dArrays.Add(item);
                        break;
                    case AudioClip m_AudioClip:
                        if (!string.IsNullOrEmpty(m_AudioClip.m_Source))
                            item.FullSize = asset.byteSize + m_AudioClip.m_Size;
                        item.Text = m_AudioClip.m_Name;
                        break;
                    case VideoClip m_VideoClip:
                        if (!string.IsNullOrEmpty(m_VideoClip.m_OriginalPath))
                            item.FullSize = asset.byteSize + m_VideoClip.m_ExternalResources.m_Size;
                        item.Text = m_VideoClip.m_Name;
                        break;
                    case Shader m_Shader:
                        item.Text = m_Shader.m_ParsedForm?.m_Name ?? m_Shader.m_Name;
                        break;
                    case MonoBehaviour m_MonoBehaviour:
                        var assetName = m_MonoBehaviour.m_Name;
                        if (m_MonoBehaviour.m_Script.TryGet(out var m_Script))
                            assetName = assetName == "" ? m_Script.m_ClassName : assetName;
                        item.Text = assetName;
                        break;
                    case GameObject m_GameObject:
                        item.Text = m_GameObject.m_Name;
                        break;
                    case Animator m_Animator:
                        if (m_Animator.m_GameObject.TryGet(out var gameObject))
                            item.Text = gameObject.m_Name;
                        break;
                    case NamedObject m_NamedObject:
                        item.Text = m_NamedObject.m_Name;
                        break;
                }
                if (string.IsNullOrEmpty(item.Text)) item.Text = item.TypeString + item.UniqueId;
                asset.Name = item.Text;
                if (include) fileAssets.Add(item);

                // Throttle progress to integer-percent changes (plus the final tick) so a
                // multi-thousand-object file cannot flood stdio with one frame per object.
                i++;
                var percent = objectCount == 0 ? 100 : (int)(100L * i / objectCount);
                if (percent != lastPercent || i == objectCount)
                {
                    lastPercent = percent;
                    Progress?.Invoke("load", i, objectCount);
                }
            }

            foreach (var item in fileAssets)
                if (containers.TryGetValue(item.Asset, out var container)) item.Container = container;

            foreach (var item in tex2dArrays)
            {
                var m_Texture2DArray = (Texture2DArray)item.Asset;
                for (var layer = 0; layer < m_Texture2DArray.m_Depth; layer++)
                    m_Texture2DArray.TextureList.Add(new Texture2D(m_Texture2DArray, layer));
            }
            Assets.AddRange(fileAssets);
        }
        for (var idx = 0; idx < Assets.Count; idx++) Assets[idx].Id = idx;
        Logger.Info($"Parsed {Assets.Count} exportable assets from {Manager.AssetsFileList.Count} files");
    }
}

public class EngineException : Exception
{
    public string Code { get; }
    public EngineException(string code, string message) : base(message) => Code = code;
}
