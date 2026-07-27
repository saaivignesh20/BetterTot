import Foundation
import XCTest
@testable import BetterTot

final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionsCompareNumericallyAndRejectInvalidInput() throws {
        let current = try XCTUnwrap(AppVersion("0.9.12"))
        let newerMinor = try XCTUnwrap(AppVersion("0.10.0"))
        let newerPatch = try XCTUnwrap(AppVersion("0.9.13"))

        XCTAssertLessThan(current, newerMinor)
        XCTAssertLessThan(current, newerPatch)
        XCTAssertEqual(AppVersion("v1.2.3"), AppVersion("1.2.3"))
        XCTAssertNil(AppVersion("1.2"))
        XCTAssertNil(AppVersion("latest"))
    }

    func testReleaseResponseProducesExpectedOutcome() async throws {
        let updateURL = try XCTUnwrap(URL(
            string: "https://github.com/saaivignesh20/BetterTot/releases/tag/v0.2.0"
        ))
        let payload = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.2.0",
            "html_url": updateURL.absoluteString,
        ])
        let checker = GitHubUpdateChecker { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (payload, response)
        }

        let outcome = try await checker.check(
            currentVersion: try XCTUnwrap(AppVersion("0.1.0"))
        )

        XCTAssertEqual(
            outcome,
            .updateAvailable(AvailableRelease(
                version: try XCTUnwrap(AppVersion("0.2.0")),
                pageURL: updateURL
            ))
        )
    }

    func testReleaseResponseHandlesCurrentVersionNoReleasesAndUnsafeURLs() async throws {
        let currentPayload = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.1.0",
            "html_url": "https://github.com/saaivignesh20/BetterTot/releases/tag/v0.1.0",
        ])
        let currentChecker = checker(status: 200, data: currentPayload)
        let currentOutcome = try await currentChecker.check(
            currentVersion: AppVersion("0.1.0")!
        )
        XCTAssertEqual(
            currentOutcome,
            .upToDate(latestVersion: AppVersion("0.1.0")!)
        )

        let emptyChecker = checker(status: 404, data: Data())
        let emptyOutcome = try await emptyChecker.check(
            currentVersion: AppVersion("0.1.0")!
        )
        XCTAssertEqual(emptyOutcome, .noPublishedReleases)

        let unsafePayload = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.2.0",
            "html_url": "http://malicious.example/update",
        ])
        let unsafeChecker = checker(status: 200, data: unsafePayload)
        await XCTAssertThrowsErrorAsync {
            _ = try await unsafeChecker.check(currentVersion: AppVersion("0.1.0")!)
        }

        let wrongRepositoryPayload = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.2.0",
            "html_url": "https://github.com/example/BetterTot/releases/tag/v0.2.0",
        ])
        let wrongRepositoryChecker = checker(status: 200, data: wrongRepositoryPayload)
        await XCTAssertThrowsErrorAsync {
            _ = try await wrongRepositoryChecker.check(currentVersion: AppVersion("0.1.0")!)
        }
    }

    func testReleaseResponseRejectsOversizedAndMalformedPayloads() async {
        let oversized = checker(status: 200, data: Data(repeating: 0x41, count: 65 * 1024))
        await XCTAssertThrowsErrorAsync {
            _ = try await oversized.check(currentVersion: AppVersion("0.1.0")!)
        }

        let malformed = checker(status: 200, data: Data("{}".utf8))
        await XCTAssertThrowsErrorAsync {
            _ = try await malformed.check(currentVersion: AppVersion("0.1.0")!)
        }

        let unavailable = checker(status: 503, data: Data())
        await XCTAssertThrowsErrorAsync {
            _ = try await unavailable.check(currentVersion: AppVersion("0.1.0")!)
        }
    }

    func testReleaseResponseRejectsAChangedResponseOrigin() async {
        let payload = try! JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.2.0",
            "html_url": "https://github.com/saaivignesh20/BetterTot/releases/tag/v0.2.0",
        ])
        let redirected = checker(
            status: 200,
            data: payload,
            responseURL: URL(string: "https://redirected.example/releases/latest")!
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await redirected.check(currentVersion: AppVersion("0.1.0")!)
        }
    }

    private func checker(
        status: Int,
        data: Data,
        responseURL: URL? = nil
    ) -> GitHubUpdateChecker {
        GitHubUpdateChecker { request in
            let response = HTTPURLResponse(
                url: responseURL ?? request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
