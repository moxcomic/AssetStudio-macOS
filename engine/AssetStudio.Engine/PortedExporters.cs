// Per-asset exporters adapted from vendored AssetStudioCLI/Exporter.cs (MIT, aelurum/AssetStudio).
// The five type exporters (Mesh/Font/Shader/VideoClip/MovieTexture) are faithful ports of the
// vendored bodies with only this mapping applied: TryExportFile(...) -> TryBuildPath(...),
// AssetItem -> EngineAssetItem, exportPath -> dir, Studio.assemblyLoader -> _assemblyLoader.
using System.Text;
using AssetStudio;
using AssetStudio.Engine.Protocol;
using SixLabors.ImageSharp;
using Object = AssetStudio.Object;

namespace AssetStudio.Engine;

public record ExportOptions(string ImageFormat);

public class PortedExporters
{
    private readonly HashSet<string> _seenPaths = new(StringComparer.OrdinalIgnoreCase);
    private readonly AssemblyLoader _assemblyLoader;

    public PortedExporters(AssemblyLoader assemblyLoader) => _assemblyLoader = assemblyLoader;

    public void ResetSession() => _seenPaths.Clear();

    public static string FixFileName(string str)
    {
        var cleaned = string.Join("_", str.Split(Path.GetInvalidFileNameChars(),
            StringSplitOptions.RemoveEmptyEntries)).TrimEnd('.').Trim();
        return string.IsNullOrEmpty(cleaned) ? "noname" : cleaned;
    }

    public bool TryBuildPath(string dir, EngineAssetItem item, string extension, out string fullPath)
    {
        Directory.CreateDirectory(dir);
        fullPath = Path.Combine(dir, FixFileName(item.Text) + extension);
        if (_seenPaths.Add(fullPath)) return true;
        // Collision suffix must be UniqueId ("_#i", session-unique across ALL loaded files), NOT PathId
        // (only unique within one SerializedFile — cross-bundle PathId ties would silently drop an asset).
        fullPath = Path.Combine(dir, FixFileName(item.Text) + item.UniqueId + extension);
        return _seenPaths.Add(fullPath);
    }

    // Resolve the image format string lazily (only the image exporters call this) so raw/dump/audio/mesh
    // never require a valid imageFormat; an unknown value on an actual image export surfaces as IO_ERROR.
    private static (ImageFormat fmt, string ext) ResolveImageFormat(string s) => s.ToLowerInvariant() switch
    {
        "png" => (ImageFormat.Png, ".png"),
        "tga" => (ImageFormat.Tga, ".tga"),
        "jpg" or "jpeg" => (ImageFormat.Jpeg, ".jpg"),
        "bmp" => (ImageFormat.Bmp, ".bmp"),
        "webp" => (ImageFormat.Webp, ".webp"),
        _ => throw new EngineException(ErrorCodes.IoError, $"unknown imageFormat {s}"),
    };

    public bool ExportConvert(EngineAssetItem item, string dir, ExportOptions options)
    {
        switch (item.Asset)
        {
            case Texture2D m_Texture2D: return ExportTexture2D(item, m_Texture2D, dir, options);
            case Texture2DArray m_Array: return ExportTexture2DArray(item, m_Array, dir, options);
            case Sprite m_Sprite: return ExportSprite(item, m_Sprite, dir, options);
            case TextAsset m_TextAsset: return ExportTextAsset(item, m_TextAsset, dir);
            case MonoBehaviour m_MonoBehaviour: return ExportMonoBehaviour(item, m_MonoBehaviour, dir);
            case AudioClip m_AudioClip: return ExportAudioClip(item, m_AudioClip, dir);
            case Animator: throw new EngineException(ErrorCodes.DecodeFailed,
                "Animator export lands in a later milestone (FBX)");
            case Mesh: return ExportMesh(item, dir);
            case Font: return ExportFont(item, dir);
            case Shader: return ExportShader(item, dir);
            case VideoClip: return ExportVideoClip(item, dir);
            case MovieTexture: return ExportMovieTexture(item, dir);
            default: return ExportRaw(item, dir);
        }
    }

    private bool ExportTexture2D(EngineAssetItem item, Texture2D m_Texture2D, string dir, ExportOptions options)
    {
        var (fmt, ext) = ResolveImageFormat(options.ImageFormat);
        if (!TryBuildPath(dir, item, ext, out var path)) return false;
        using var image = m_Texture2D.ConvertToImage(flip: true);
        if (image == null) throw new EngineException(ErrorCodes.DecodeFailed,
            $"texture decode failed ({m_Texture2D.m_TextureFormat})");
        using var fs = File.Create(path); // truncates — File.OpenWrite would leave a stale tail on a shorter re-export
        image.WriteToStream(fs, fmt);
        return true;
    }

    private bool ExportTexture2DArray(EngineAssetItem item, Texture2DArray m_Array, string dir, ExportOptions options)
    {
        var ok = 0;
        for (var layer = 0; layer < m_Array.TextureList.Count; layer++)
        {
            var fake = m_Array.TextureList[layer];
            var layerItem = new EngineAssetItem(fake) { Id = item.Id, Text = $"{item.Text}_{layer}" };
            try { if (ExportTexture2D(layerItem, fake, dir, options)) ok++; }
            catch { /* keep exporting layers; caller-level error granularity */ }
        }
        return ok > 0;
    }

    private bool ExportSprite(EngineAssetItem item, Sprite m_Sprite, string dir, ExportOptions options)
    {
        var (fmt, ext) = ResolveImageFormat(options.ImageFormat);
        if (!TryBuildPath(dir, item, ext, out var path)) return false;
        using var image = m_Sprite.GetImage();
        if (image == null) throw new EngineException(ErrorCodes.DecodeFailed, "sprite image unavailable");
        using var fs = File.Create(path); // truncates — see ExportTexture2D
        image.WriteToStream(fs, fmt);
        return true;
    }

    private bool ExportTextAsset(EngineAssetItem item, TextAsset m_TextAsset, string dir)
    {
        var ext = Path.GetExtension(item.Container);
        if (string.IsNullOrEmpty(ext)) ext = ".txt";
        if (!TryBuildPath(dir, item, ext, out var path)) return false;
        File.WriteAllBytes(path, m_TextAsset.m_Script);
        return true;
    }

    private bool ExportMonoBehaviour(EngineAssetItem item, MonoBehaviour m_MonoBehaviour, string dir)
    {
        if (!TryBuildPath(dir, item, ".json", out var path)) return false;
        // Mirrors vendored ExportMonoBehaviour (Exporter.cs:133-153): ToType() then type-tree fallback.
        var type = m_MonoBehaviour.ToType();
        if (type == null)
        {
            var m_Type = m_MonoBehaviour.ConvertToTypeTree(_assemblyLoader);
            type = m_MonoBehaviour.ToType(m_Type);
        }
        if (type == null) throw new EngineException(ErrorCodes.DecodeFailed, "MonoBehaviour type unresolvable");
        File.WriteAllText(path, Newtonsoft.Json.JsonConvert.SerializeObject(type, Newtonsoft.Json.Formatting.Indented));
        return true;
    }

    private bool ExportAudioClip(EngineAssetItem item, AudioClip m_AudioClip, string dir)
    {
        // Mirrors vendored ExportAudioClip: raw data via m_AudioData.GetData(); FSB->wav via AudioClipConverter.
        var m_AudioData = m_AudioClip.m_AudioData.GetData();
        if (m_AudioData == null || m_AudioData.Length == 0)
            throw new EngineException(ErrorCodes.DecodeFailed, "audio data unavailable");
        var converter = new AudioClipConverter(m_AudioClip);
        if (converter.IsSupport)
        {
            if (!TryBuildPath(dir, item, ".wav", out var path)) return false;
            var debugLog = string.Empty;
            var buffer = converter.ConvertToWav(m_AudioData, ref debugLog);
            if (buffer == null) throw new EngineException(ErrorCodes.DecodeFailed,
                $"FSB->wav conversion failed. {debugLog}");
            File.WriteAllBytes(path, buffer);
        }
        else
        {
            if (!TryBuildPath(dir, item, converter.GetExtensionName(), out var path)) return false;
            File.WriteAllBytes(path, m_AudioData);
        }
        return true;
    }

    public bool ExportRaw(EngineAssetItem item, string dir)
    {
        if (!TryBuildPath(dir, item, ".dat", out var path)) return false;
        // Mirrors vendored ExportRawFile: GetRawData().
        File.WriteAllBytes(path, item.Asset.GetRawData());
        return true;
    }

    public bool ExportDump(EngineAssetItem item, string dir)
    {
        if (!TryBuildPath(dir, item, ".txt", out var path)) return false;
        string? str = null;
        try { str = item.Asset.Dump(); } catch { }
        if (str == null && item.Asset is MonoBehaviour m_MonoBehaviour)
        {
            var m_Type = m_MonoBehaviour.ConvertToTypeTree(_assemblyLoader);
            str = m_MonoBehaviour.Dump(m_Type);
        }
        try { str ??= item.Asset.DumpObject(); } catch { }
        if (string.IsNullOrEmpty(str)) throw new EngineException(ErrorCodes.DecodeFailed, "nothing to dump");
        File.WriteAllText(path, str);
        return true;
    }

    // ---- five ported bodies (faithful adaptations of vendored Exporter.cs) ----

    // Vendored Exporter.cs:175-265. ProcessData, vertex/UV/normal/face emission, NaN->0, write .obj.
    private bool ExportMesh(EngineAssetItem item, string dir)
    {
        var m_Mesh = (Mesh)item.Asset;
        m_Mesh.ProcessData();

        if (m_Mesh.m_VertexCount <= 0)
            return false;
        if (!TryBuildPath(dir, item, ".obj", out var exportFullPath))
            return false;

        var sb = new StringBuilder();
        sb.AppendLine("g " + m_Mesh.m_Name);

        #region Vertices
        if (m_Mesh.m_Vertices == null || m_Mesh.m_Vertices.Length == 0)
        {
            return false;
        }

        int c = 3;
        if (m_Mesh.m_Vertices.Length == m_Mesh.m_VertexCount * 4)
        {
            c = 4;
        }

        for (int v = 0; v < m_Mesh.m_VertexCount; v++)
        {
            sb.Append($"v {-m_Mesh.m_Vertices[v * c]} {m_Mesh.m_Vertices[v * c + 1]} {m_Mesh.m_Vertices[v * c + 2]}\r\n");
        }
        #endregion

        #region UV
        if (m_Mesh.m_UV0?.Length > 0)
        {
            c = 4;
            if (m_Mesh.m_UV0.Length == m_Mesh.m_VertexCount * 2)
            {
                c = 2;
            }
            else if (m_Mesh.m_UV0.Length == m_Mesh.m_VertexCount * 3)
            {
                c = 3;
            }

            for (int v = 0; v < m_Mesh.m_VertexCount; v++)
            {
                sb.AppendFormat("vt {0} {1}\r\n", m_Mesh.m_UV0[v * c], m_Mesh.m_UV0[v * c + 1]);
            }
        }
        #endregion

        #region Normals
        if (m_Mesh.m_Normals?.Length > 0)
        {
            if (m_Mesh.m_Normals.Length == m_Mesh.m_VertexCount * 3)
            {
                c = 3;
            }
            else if (m_Mesh.m_Normals.Length == m_Mesh.m_VertexCount * 4)
            {
                c = 4;
            }

            for (int v = 0; v < m_Mesh.m_VertexCount; v++)
            {
                sb.AppendFormat("vn {0} {1} {2}\r\n", -m_Mesh.m_Normals[v * c], m_Mesh.m_Normals[v * c + 1], m_Mesh.m_Normals[v * c + 2]);
            }
        }
        #endregion

        #region Face
        int sum = 0;
        for (var i = 0; i < m_Mesh.m_SubMeshes.Count; i++)
        {
            sb.AppendLine($"g {m_Mesh.m_Name}_{i}");
            int indexCount = (int)m_Mesh.m_SubMeshes[i].indexCount;
            var end = sum + indexCount / 3;
            for (int f = sum; f < end; f++)
            {
                sb.AppendFormat("f {0}/{0}/{0} {1}/{1}/{1} {2}/{2}/{2}\r\n", m_Mesh.m_Indices[f * 3 + 2] + 1, m_Mesh.m_Indices[f * 3 + 1] + 1, m_Mesh.m_Indices[f * 3] + 1);
            }

            sum = end;
        }
        #endregion

        sb.Replace("NaN", "0");
        File.WriteAllText(exportFullPath, sb.ToString());
        Logger.Debug($"{item.TypeString} \"{item.Text}\" exported to \"{exportFullPath}\"");
        return true;
    }

    // Vendored Exporter.cs:155-173. .ttf, or .otf when the OTTO magic is present.
    private bool ExportFont(EngineAssetItem item, string dir)
    {
        var m_Font = (Font)item.Asset;
        if (m_Font.m_FontData != null)
        {
            var extension = ".ttf";
            if (m_Font.m_FontData[0] == 79 && m_Font.m_FontData[1] == 84 && m_Font.m_FontData[2] == 84 && m_Font.m_FontData[3] == 79)
            {
                extension = ".otf";
            }
            if (!TryBuildPath(dir, item, extension, out var exportFullPath))
                return false;
            File.WriteAllBytes(exportFullPath, m_Font.m_FontData);

            Logger.Debug($"{item.TypeString} \"{item.Text}\" exported to \"{exportFullPath}\"");
            return true;
        }
        return false;
    }

    // Vendored Exporter.cs:94-104. m_Shader.Convert() -> .shader.
    private bool ExportShader(EngineAssetItem item, string dir)
    {
        if (!TryBuildPath(dir, item, ".shader", out var exportFullPath))
            return false;
        var m_Shader = (Shader)item.Asset;
        var str = m_Shader.Convert();
        File.WriteAllText(exportFullPath, str);

        Logger.Debug($"{item.TypeString} \"{item.Text}\" exported to \"{exportFullPath}\"");
        return true;
    }

    // Vendored Exporter.cs:57-81. m_VideoData.WriteData to the original extension (CLIOptions-gated
    // debug metadata logging dropped — pure diagnostics, no effect on output).
    private bool ExportVideoClip(EngineAssetItem item, string dir)
    {
        var m_VideoClip = (VideoClip)item.Asset;
        if (m_VideoClip.m_ExternalResources.m_Size > 0)
        {
            if (!TryBuildPath(dir, item, Path.GetExtension(m_VideoClip.m_OriginalPath), out var exportFullPath))
                return false;

            m_VideoClip.m_VideoData.WriteData(exportFullPath);
            Logger.Debug($"{item.TypeString} \"{item.Text}\" exported to \"{exportFullPath}\"");
            return true;
        }
        return false;
    }

    // Vendored Exporter.cs:83-92. m_MovieData -> .ogv.
    private bool ExportMovieTexture(EngineAssetItem item, string dir)
    {
        var m_MovieTexture = (MovieTexture)item.Asset;
        if (!TryBuildPath(dir, item, ".ogv", out var exportFullPath))
            return false;
        File.WriteAllBytes(exportFullPath, m_MovieTexture.m_MovieData);

        Logger.Debug($"{item.TypeString} \"{item.Text}\" exported to \"{exportFullPath}\"");
        return true;
    }
}
