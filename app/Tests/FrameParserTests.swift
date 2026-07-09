import XCTest
@testable import AssetStudio

final class FrameParserTests: XCTestCase {
    func frame(_ json: String) -> Data {
        let body = Data(json.utf8)
        return Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    }

    func testSingleFrame() {
        var p = FrameParser()
        let out = p.feed(frame(#"{"a":1}"#))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(String(decoding: out[0], as: UTF8.self), #"{"a":1}"#)
    }

    func testSplitAcrossChunks() {
        var p = FrameParser()
        let f = frame(#"{"hello":"world"}"#)
        let cut = f.count / 2
        XCTAssertTrue(p.feed(f.prefix(cut)).isEmpty)
        let out = p.feed(f.suffix(from: cut))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(String(decoding: out[0], as: UTF8.self), #"{"hello":"world"}"#)
    }

    func testTwoFramesOneChunk() {
        var p = FrameParser()
        let out = p.feed(frame(#"{"n":1}"#) + frame(#"{"n":2}"#))
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(String(decoding: out[0], as: UTF8.self), #"{"n":1}"#)
        XCTAssertEqual(String(decoding: out[1], as: UTF8.self), #"{"n":2}"#)
    }

    func testCaseInsensitiveHeaderAndExtraHeaders() {
        var p = FrameParser()
        let body = Data(#"{"x":true}"#.utf8)
        let raw = Data("content-length: \(body.count)\r\nContent-Type: application/json\r\n\r\n".utf8) + body
        let out = p.feed(raw)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(String(decoding: out[0], as: UTF8.self), #"{"x":true}"#)
    }

    func testUTF8BodyLengthInBytes() {
        var p = FrameParser()
        let json = #"{"name":"雪"}"#   // "雪" is 3 UTF-8 bytes: length must be byte-counted
        let out = p.feed(frame(json))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(String(decoding: out[0], as: UTF8.self), json)
    }

    func testZeroLengthBody() {
        var p = FrameParser()
        let out = p.feed(Data("Content-Length: 0\r\n\r\n".utf8))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 0)
    }

    func testMalformedHeaderThenValidRecovers() {
        var p = FrameParser()
        // A header block with no Content-Length is skipped; the next valid frame parses.
        let malformed = Data("X-Bad: nope\r\n\r\n".utf8)
        let out = p.feed(malformed + frame(#"{"ok":true}"#))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(String(decoding: out[0], as: UTF8.self), #"{"ok":true}"#)
    }
}
