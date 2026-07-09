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
    }

    func testCaseInsensitiveHeaderAndExtraHeaders() {
        var p = FrameParser()
        let body = Data(#"{"x":true}"#.utf8)
        let raw = Data("content-length: \(body.count)\r\nContent-Type: application/json\r\n\r\n".utf8) + body
        XCTAssertEqual(p.feed(raw).count, 1)
    }

    func testUTF8BodyLengthInBytes() {
        var p = FrameParser()
        let out = p.feed(frame(#"{"name":"雪"}"#))
        XCTAssertEqual(out.count, 1)
    }
}
