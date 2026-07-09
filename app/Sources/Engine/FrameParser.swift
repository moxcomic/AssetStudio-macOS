import Foundation

/// Incremental LSP-style framing parser: `Content-Length: N\r\n\r\n<body>`.
struct FrameParser {
    private var buffer = Data()
    private static let separator = Data("\r\n\r\n".utf8)

    mutating func feed(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while true {
            guard let sep = buffer.firstRange(of: Self.separator) else { break }
            let headerLen = buffer.distance(from: buffer.startIndex, to: sep.lowerBound)
            let header = String(decoding: buffer.prefix(headerLen), as: UTF8.self)
            var contentLength: Int?
            for line in header.split(separator: "\r\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2,
                   parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                    contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces))
                }
            }
            guard let length = contentLength else {
                buffer.removeFirst(headerLen + Self.separator.count)   // malformed header: skip it
                continue
            }
            let total = headerLen + Self.separator.count + length
            guard buffer.count >= total else { break }
            frames.append(Data(buffer.dropFirst(headerLen + Self.separator.count).prefix(length)))
            buffer.removeFirst(total)
        }
        return frames
    }
}
