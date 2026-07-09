namespace AssetStudio.Engine.Protocol;

public record NativeCaps(bool Texture, bool Fbx, bool Fmod);
public record InitializeResult(string EngineVersion, string CoreVersion, NativeCaps Natives);
public record LoadResult(int LoadedFiles, int AssetCount, string? UnityVersion);
public record AssetRowDto(int Id, string Name, string Container, string Type, long PathId, long Size, string SourceFile);
public record ListResult(int Total, IReadOnlyList<AssetRowDto> Rows);
public record ProgressNote(string Token, int Current, int Total, string? Message);
public record LogNote(string Level, string Message);
public record ExportErrorDto(int Id, string Name, string Message);
public record ExportResult(int Exported, int Skipped, List<ExportErrorDto> Errors);

public static class ErrorCodes
{
    public const string NoWorkspace = "NO_WORKSPACE";
    public const string BadId = "BAD_ID";
    public const string DecodeFailed = "DECODE_FAILED";
    public const string IoError = "IO_ERROR";
    public const string InvalidPaths = "INVALID_PATHS";
    public const string LoadFailed = "LOAD_FAILED";
    public const string Cancelled = "CANCELLED";
}
