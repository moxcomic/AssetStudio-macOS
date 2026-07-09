using AssetStudio;
using AssetStudio.Engine.Protocol;

namespace AssetStudio.Engine;

public record ExportRequestOptions(string Mode, string DestDir, string GroupBy, string ImageFormat);

public class ExportService
{
    private readonly Workspace _workspace;
    private readonly PortedExporters _exporters;
    public event Action<int, int>? Progress;

    public ExportService(Workspace workspace, AssemblyLoader assemblyLoader)
    {
        _workspace = workspace;
        _exporters = new PortedExporters(assemblyLoader);
    }

    public ExportResult Export(int[] ids, ExportRequestOptions req, CancellationToken ct)
    {
        if (!Directory.Exists(req.DestDir))
            throw new EngineException(ErrorCodes.IoError, $"destination does not exist: {req.DestDir}");
        // imageFormat is validated lazily inside the image exporters — raw/dump/audio must not require it.
        var options = new ExportOptions(req.ImageFormat);
        var fullDest = Path.GetFullPath(req.DestDir);
        _exporters.ResetSession();

        int exported = 0, skipped = 0;
        var errors = new List<ExportErrorDto>();
        for (var n = 0; n < ids.Length; n++)
        {
            ct.ThrowIfCancellationRequested();
            var id = ids[n];
            EngineAssetItem? item = null;
            try
            {
                item = _workspace.Get(id); // inside the try so a bad id is a per-asset error, not a batch abort
                // Grouping mirrors vendored Studio.ExportAssets group options.
                var dir = req.GroupBy switch
                {
                    "typeName" => Path.Combine(req.DestDir, item.TypeString),
                    "containerPath" or "containerPathFull" when !string.IsNullOrEmpty(item.Container) =>
                        req.GroupBy == "containerPathFull"
                            ? Path.Combine(req.DestDir, Path.GetDirectoryName(item.Container) ?? "",
                                Path.GetFileNameWithoutExtension(item.Container))
                            : Path.Combine(req.DestDir, Path.GetDirectoryName(item.Container) ?? ""),
                    "sourceFileName" => item.SourceFile.originalPath == null
                        ? Path.Combine(req.DestDir, item.SourceFile.fileName + "_export")
                        : Path.Combine(req.DestDir, Path.GetFileName(item.SourceFile.originalPath) + "_export",
                            item.SourceFile.fileName),
                    _ => req.DestDir,
                };
                // Containment: item.Container is hostile-controllable bundle data (may hold ".." or a rooted
                // path); reject anything that resolves outside destDir before any file is written.
                var fullDir = Path.GetFullPath(dir);
                if (fullDir != fullDest && !fullDir.StartsWith(fullDest + Path.DirectorySeparatorChar, StringComparison.Ordinal))
                    throw new EngineException(ErrorCodes.IoError, $"grouping path escapes destination: {item.Container}");

                var ok = req.Mode switch
                {
                    "convert" => _exporters.ExportConvert(item, dir, options),
                    "raw" => _exporters.ExportRaw(item, dir),
                    "dump" => _exporters.ExportDump(item, dir),
                    _ => throw new EngineException(ErrorCodes.IoError, $"unknown mode {req.Mode}"),
                };
                if (ok) exported++; else skipped++;
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception e)
            {
                errors.Add(new ExportErrorDto(id, item?.Text ?? "", e.Message));
            }
            Progress?.Invoke(n + 1, ids.Length);
        }
        // skipped = asset produced no file: a dedupe-collision (name already used this session) OR the
        // exporter reported nothing exportable (empty mesh, null font data, video with no external resource).
        return new ExportResult(exported, skipped, errors);
    }
}
