import XCTest
@testable import AssetStudio

/// Pure tests for EngineClient.decode — the response demux / notification decode
/// that a live engine would otherwise be the only way to exercise.
private struct Int64Holder: Codable { let pathId: Int64 }

final class EngineDecodeTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    // (a) success result → .response carrying the result JSON
    func testSuccessResult() {
        let frame = data(#"{"jsonrpc":"2.0","id":7,"result":{"loadedFiles":3,"assetCount":10,"unityVersion":"2020.3"}}"#)
        guard case let .response(id, result) = EngineClient.decode(frame) else {
            return XCTFail("expected .response")
        }
        XCTAssertEqual(id, 7)
        let decoded = try? JSONDecoder().decode(LoadResult.self, from: result)
        XCTAssertEqual(decoded?.loadedFiles, 3)
        XCTAssertEqual(decoded?.assetCount, 10)
        XCTAssertEqual(decoded?.unityVersion, "2020.3")
    }

    // (b) error with data.code → that code is used
    func testErrorWithDataCode() {
        let frame = data(#"{"jsonrpc":"2.0","id":9,"error":{"message":"boom","data":{"code":"E_LOAD"}}}"#)
        guard case let .failure(id, err) = EngineClient.decode(frame) else {
            return XCTFail("expected .failure")
        }
        XCTAssertEqual(id, 9)
        XCTAssertEqual(err.code, "E_LOAD")
        XCTAssertEqual(err.message, "boom")
    }

    // (c) error without data → fallback code
    func testErrorWithoutDataUsesFallbackCode() {
        let frame = data(#"{"jsonrpc":"2.0","id":4,"error":{"message":"nope"}}"#)
        guard case let .failure(id, err) = EngineClient.decode(frame) else {
            return XCTFail("expected .failure")
        }
        XCTAssertEqual(id, 4)
        XCTAssertEqual(err.code, "ENGINE_ERROR")
        XCTAssertEqual(err.message, "nope")
    }

    // (d) null result → normalized to {}, decodes as EmptyResult
    func testNullResultNormalizesToEmpty() {
        let frame = data(#"{"jsonrpc":"2.0","id":1,"result":null}"#)
        guard case let .response(id, result) = EngineClient.decode(frame) else {
            return XCTFail("expected .response")
        }
        XCTAssertEqual(id, 1)
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "{}")
        XCTAssertNoThrow(try JSONDecoder().decode(EmptyResult.self, from: result))
    }

    // (e) pathId = Int64.max survives the JSONSerialization round-trip losslessly
    func testInt64MaxRoundTrip() {
        let frame = data(#"{"jsonrpc":"2.0","id":2,"result":{"pathId":9223372036854775807}}"#)
        guard case let .response(_, result) = EngineClient.decode(frame) else {
            return XCTFail("expected .response")
        }
        let decoded = try? JSONDecoder().decode(Int64Holder.self, from: result)
        XCTAssertEqual(decoded?.pathId, Int64.max)
    }

    // (d') a scalar top-level result must NOT crash (JSONSerialization would
    // raise an uncatchable ObjC exception without .fragmentsAllowed).
    func testScalarResultDoesNotCrash() {
        let frame = data(#"{"jsonrpc":"2.0","id":5,"result":42}"#)
        guard case let .response(id, result) = EngineClient.decode(frame) else {
            return XCTFail("expected .response")
        }
        XCTAssertEqual(id, 5)
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "42")
    }

    // (f) notification decode: progress + log
    func testProgressNotificationDecode() {
        let frame = data(#"{"jsonrpc":"2.0","method":"progress","params":{"token":"load","current":2,"total":5,"message":"loading"}}"#)
        guard case let .notification(.progress(note)) = EngineClient.decode(frame) else {
            return XCTFail("expected .progress notification")
        }
        XCTAssertEqual(note.token, "load")
        XCTAssertEqual(note.current, 2)
        XCTAssertEqual(note.total, 5)
        XCTAssertEqual(note.message, "loading")
    }

    func testLogNotificationDecode() {
        let frame = data(#"{"jsonrpc":"2.0","method":"log","params":{"level":"warn","message":"hi"}}"#)
        guard case let .notification(.log(note)) = EngineClient.decode(frame) else {
            return XCTFail("expected .log notification")
        }
        XCTAssertEqual(note.level, "warn")
        XCTAssertEqual(note.message, "hi")
    }
}
