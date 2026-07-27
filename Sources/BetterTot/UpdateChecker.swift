import Foundation

private final class UpdateSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct AvailableRelease: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
}

enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate(latestVersion: AppVersion)
    case updateAvailable(AvailableRelease)
    case noPublishedReleases
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case responseTooLarge
    case serviceUnavailable
    case unsafeReleaseURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The update service returned an invalid response."
        case .responseTooLarge:
            "The update response was unexpectedly large."
        case .serviceUnavailable:
            "The update service is unavailable right now."
        case .unsafeReleaseURL:
            "The update service returned an unsafe release link."
        }
    }
}

struct GitHubUpdateChecker: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct ReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private static let endpoint = URL(
        string: "https://api.github.com/repos/saaivignesh20/BetterTot/releases/latest"
    )!
    private static let maximumResponseBytes = 64 * 1024

    private let load: Loader

    init(load: @escaping Loader) {
        self.load = load
    }

    func check(currentVersion: AppVersion) async throws -> UpdateCheckOutcome {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BetterTot/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await load(request)
        guard response.url == Self.endpoint else {
            throw UpdateCheckError.invalidResponse
        }
        if response.statusCode == 404 {
            return .noPublishedReleases
        }
        guard response.statusCode == 200 else {
            throw UpdateCheckError.serviceUnavailable
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw UpdateCheckError.responseTooLarge
        }
        guard let release = try? JSONDecoder().decode(ReleaseResponse.self, from: data),
              let version = AppVersion(release.tagName) else {
            throw UpdateCheckError.invalidResponse
        }
        guard release.htmlURL.scheme == "https",
              release.htmlURL.host?.lowercased() == "github.com",
              release.htmlURL.user == nil,
              release.htmlURL.password == nil,
              release.htmlURL.port == nil,
              release.htmlURL.query == nil,
              release.htmlURL.fragment == nil,
              release.htmlURL.pathComponents == [
                  "/",
                  "saaivignesh20",
                  "BetterTot",
                  "releases",
                  "tag",
                  release.tagName,
              ] else {
            throw UpdateCheckError.unsafeReleaseURL
        }
        if version > currentVersion {
            return .updateAvailable(AvailableRelease(
                version: version,
                pageURL: release.htmlURL
            ))
        }
        return .upToDate(latestVersion: version)
    }

    static func live() -> GitHubUpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(
            configuration: configuration,
            delegate: UpdateSessionDelegate(),
            delegateQueue: nil
        )
        return GitHubUpdateChecker { request in
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw UpdateCheckError.invalidResponse
            }
            var data = Data()
            data.reserveCapacity(Self.maximumResponseBytes)
            for try await byte in bytes {
                guard data.count < Self.maximumResponseBytes else {
                    throw UpdateCheckError.responseTooLarge
                }
                data.append(byte)
            }
            return (data, response)
        }
    }
}
