using AssetStudio;
using AssetStudio.Engine.Protocol;

namespace AssetStudio.Engine;

public class RpcLogger : ILogger
{
    private readonly Action<LogNote> _emit;
    public RpcLogger(Action<LogNote> emit) => _emit = emit;

    public void Log(LoggerEvent loggerEvent, string message, bool ignoreLevel = false)
    {
        var level = loggerEvent switch
        {
            LoggerEvent.Error => "error",
            LoggerEvent.Warning => "warning",
            LoggerEvent.Debug => "debug",
            _ => "info",
        };
        _emit(new LogNote(level, message));
        Console.Error.WriteLine($"[{level}] {message}");
    }
}
