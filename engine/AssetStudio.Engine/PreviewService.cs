using System.Text;
using AssetStudio;
using AssetStudio.Engine.Protocol;
using Newtonsoft.Json;
using SixLabors.ImageSharp;
using Object = AssetStudio.Object;

namespace AssetStudio.Engine;

// path/text are marked NullValueHandling.Include so they serialize as explicit `null` (the wire
// contract lists them as present-nullable); StreamJsonRpc's formatter otherwise omits null members.
public record PreviewResult(
    string Kind,
    [property: JsonProperty(NullValueHandling = NullValueHandling.Include)] string? Path,
    [property: JsonProperty(NullValueHandling = NullValueHandling.Include)] string? Text,
    PreviewMeta Meta);
public record PreviewMeta(string Name, string Type, string Container, long PathId, long Size,
    Dictionary<string, string> Extra);

public class PreviewService
{
    private const int InlineTextCap = 262_144;
    private readonly SessionTempDir _tmp;
    private readonly AssemblyLoader _assemblyLoader;
    private readonly Dictionary<int, PreviewResult> _cache = new();

    public PreviewService(SessionTempDir tmp, AssemblyLoader assemblyLoader)
    {
        _tmp = tmp;
        _assemblyLoader = assemblyLoader;
    }

    public void InvalidateAll() { _cache.Clear(); _tmp.Clear(); }

    public PreviewResult Preview(EngineAssetItem item)
    {
        if (_cache.TryGetValue(item.Id, out var hit)) return hit;
        var result = Build(item);
        _cache[item.Id] = result;
        return result;
    }

    private PreviewResult Build(EngineAssetItem item)
    {
        var extra = new Dictionary<string, string>();
        string kind = "none";
        string? path = null;
        string? text = null;

        switch (item.Asset)
        {
            case Texture2D m_Texture2D:
            {
                extra["Width"] = m_Texture2D.m_Width.ToString();
                extra["Height"] = m_Texture2D.m_Height.ToString();
                extra["Format"] = m_Texture2D.m_TextureFormat.ToString();
                extra["MipCount"] = m_Texture2D.m_MipCount.ToString();
                using var image = m_Texture2D.ConvertToImage(flip: true)
                    ?? throw new EngineException(ErrorCodes.DecodeFailed,
                        $"texture decode failed ({m_Texture2D.m_TextureFormat})");
                path = _tmp.PathFor($"p_{item.Id}.png");
                image.SaveAsPng(path);
                kind = "image";
                break;
            }
            case Texture2DArray m_Texture2DArray:
            {
                extra["Depth"] = m_Texture2DArray.m_Depth.ToString();
                var first = m_Texture2DArray.TextureList.FirstOrDefault();
                if (first != null)
                {
                    using var image = first.ConvertToImage(flip: true);
                    if (image != null)
                    {
                        path = _tmp.PathFor($"p_{item.Id}.png");
                        image.SaveAsPng(path);
                        kind = "image";
                        extra["Note"] = "layer 0 of array";
                    }
                }
                break;
            }
            case Sprite m_Sprite:
            {
                extra["Rect"] = $"{m_Sprite.m_Rect.width}x{m_Sprite.m_Rect.height}";
                using var image = m_Sprite.GetImage()
                    ?? throw new EngineException(ErrorCodes.DecodeFailed, "sprite image unavailable");
                path = _tmp.PathFor($"p_{item.Id}.png");
                image.SaveAsPng(path);
                kind = "image";
                break;
            }
            case TextAsset m_TextAsset:
            {
                var bytes = m_TextAsset.m_Script;
                extra["Bytes"] = bytes.Length.ToString();
                kind = "text";
                var str = TryDecodeUtf8(bytes) ?? BitConverter.ToString(
                    bytes, 0, Math.Min(bytes.Length, 512)).Replace("-", " ");
                (text, path) = Deliver(str, item.Id);
                break;
            }
            case MonoBehaviour m_MonoBehaviour:
            {
                if (m_MonoBehaviour.m_Script.TryGet(out var script))
                    extra["Script"] = script.m_ClassName;
                kind = "text";
                (text, path) = Deliver(DumpAsset(item.Asset), item.Id);
                break;
            }
            case Shader m_Shader:
            {
                kind = "text";
                string str;
                try { str = m_Shader.Convert() ?? "// shader conversion returned nothing"; }
                catch (Exception e) { str = $"// shader conversion failed: {e.Message}"; }
                (text, path) = Deliver(str, item.Id);
                break;
            }
            case AudioClip m_AudioClip:
            {
                extra["Channels"] = m_AudioClip.m_Channels.ToString();
                extra["Frequency"] = m_AudioClip.m_Frequency.ToString();
                extra["Length"] = m_AudioClip.m_Length.ToString("F2");
                break; // audio preview lands with the audio milestone
            }
            case Mesh m_Mesh:
            {
                extra["Vertices"] = m_Mesh.m_VertexCount.ToString();
                break; // 3D viewport lands with the 3D milestone
            }
            default:
            {
                var dump = DumpAsset(item.Asset);
                if (!string.IsNullOrEmpty(dump)) { kind = "text"; (text, path) = Deliver(dump, item.Id); }
                break;
            }
        }

        return new PreviewResult(kind, path, text,
            new PreviewMeta(item.Text, item.TypeString, item.Container, item.PathId, item.FullSize, extra));
    }

    // Mirrors vendored ExportDumpFile (AssetStudioCLI/Exporter.cs:350-372):
    // Dump() → MonoBehaviour type-tree fallback → DumpObject().
    private string DumpAsset(Object asset)
    {
        string? str = null;
        try { str = asset.Dump(); } catch { }
        if (str == null && asset is MonoBehaviour m_MonoBehaviour)
        {
            try
            {
                var m_Type = m_MonoBehaviour.ConvertToTypeTree(_assemblyLoader);
                str = m_MonoBehaviour.Dump(m_Type);
            }
            catch (Exception e) { str = $"// type-tree dump failed: {e.Message}"; }
        }
        try { str ??= asset.DumpObject(); } catch { }
        return str ?? string.Empty;
    }

    private (string? inline, string? file) Deliver(string content, int id)
    {
        if (Encoding.UTF8.GetByteCount(content) <= InlineTextCap) return (content, null);
        var p = _tmp.PathFor($"p_{id}.txt");
        File.WriteAllText(p, content);
        return (null, p);
    }

    private static string? TryDecodeUtf8(byte[] bytes)
    {
        try
        {
            var s = new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(bytes);
            return s.Contains('\0') ? null : s;
        }
        catch { return null; }
    }
}
