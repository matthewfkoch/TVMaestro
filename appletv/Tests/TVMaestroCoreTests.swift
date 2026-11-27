import Foundation

private var failures = 0

private func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        fputs("FAIL \(file):\(line): \(message)\n", stderr)
        failures += 1
    }
}

private func runAllTests() {
    // 1. LayoutGeometry
    expect(LayoutGeometry.capacity("1") == 1, "1 capacity should be 1")
    expect(LayoutGeometry.capacity("2x1") == 2, "2x1 capacity should be 2")
    expect(LayoutGeometry.capacity("1x2") == 2, "1x2 capacity should be 2")
    expect(LayoutGeometry.capacity("2x2") == 4, "2x2 capacity should be 4")
    expect(LayoutGeometry.capacity("3x3") == 9, "3x3 capacity should be 9")
    expect(LayoutGeometry.capacity("unknown") == 1, "unknown defaults to 1")

    // 2. SessionSlot playability & decoding defaults
    expect(!SessionSlot(url: nil).isPlayable, "nil url is not playable")
    expect(!SessionSlot(url: "   ").isPlayable, "blank url is not playable")
    expect(SessionSlot(url: "http://dvr.local/espn.ts").isPlayable, "valid url is playable")

    let decoded = try? JSONDecoder().decode(
        PlaybackSession.self,
        from: Data(#"{"layout":"2x2","slots":[{"url":"http://a.ts","audio":true}]}"#.utf8)
    )
    expect(decoded?.layout == "2x2", "decoded layout should be 2x2")
    expect(decoded?.mode == "single", "missing mode defaults to single")
    expect(decoded?.slots.count == 1 && decoded?.slots[0].audio == true, "decoded slot preserved")

    // 3. TinyHTTPServer.parseRequestResult
    let validGet = Data("GET /api/health?foo=1 HTTP/1.1\r\nHost: tv.local\r\nX-Auth-Token: abc\r\n\r\n".utf8)
    if case .ok(let parsed) = TinyHTTPServer.parseRequestResult(validGet) {
        expect(parsed.method == "GET", "method should be GET")
        expect(parsed.path == "/api/health", "query string stripped from path")
        expect(parsed.headers["x-auth-token"] == "abc", "header lowercased")
        expect(parsed.body.isEmpty, "GET body empty")
    } else {
        expect(false, "valid GET should parse as .ok")
    }

    let postBody = #"{"index":2}"#
    let validPost = Data("POST /api/session/audio HTTP/1.1\r\nContent-Length: \(postBody.utf8.count)\r\n\r\n\(postBody)".utf8)
    if case .ok(let parsed) = TinyHTTPServer.parseRequestResult(validPost) {
        expect(parsed.method == "POST", "method should be POST")
        expect(String(data: parsed.body, encoding: .utf8) == postBody, "POST body preserved")
    } else {
        expect(false, "valid POST should parse as .ok")
    }

    // Partial body -> .incomplete
    let partialPost = Data("POST /api/session HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"short\":1}".utf8)
    expect(TinyHTTPServer.parseRequestResult(partialPost) == .incomplete, "partial body must be .incomplete")

    // Negative Content-Length -> .invalid (must never crash!)
    let negativeLen = Data("POST /api/session HTTP/1.1\r\nContent-Length: -5\r\n\r\nhello".utf8)
    expect(TinyHTTPServer.parseRequestResult(negativeLen) == .invalid, "negative content-length must be .invalid")

    // Non-numeric Content-Length -> .invalid
    let badLen = Data("POST /api/session HTTP/1.1\r\nContent-Length: nope\r\n\r\n".utf8)
    expect(TinyHTTPServer.parseRequestResult(badLen) == .invalid, "non-numeric content-length must be .invalid")

    // Oversized Content-Length -> .tooLarge
    let hugeLen = Data("POST /api/session HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)
    expect(TinyHTTPServer.parseRequestResult(hugeLen) == .tooLarge, "oversized content-length must be .tooLarge")

    if failures > 0 {
        fputs("\(failures) Apple TV core test(s) failed.\n", stderr)
        exit(1)
    }
    print("Apple TV core tests passed.")
}

@main
struct TVMaestroCoreTests {
    static func main() {
        runAllTests()
    }
}
