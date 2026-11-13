import Foundation
import Testing
@testable import WeatherCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    struct ManifestEntry: Decodable {
        let url: String
        let status: Int
    }

    static func manifest() throws -> [String: ManifestEntry] {
        try JSONDecoder().decode([String: ManifestEntry].self, from: data("manifest"))
    }
}

extension LocalDate {
    /// Parses "yyyy-MM-dd".
    init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}

struct StubTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

actor CallLog {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

func httpResponse(_ status: Int, url: URL = URL(fileURLWithPath: "/")) -> HTTPURLResponse {
    guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
        preconditionFailure("HTTPURLResponse must build for a valid status code")
    }
    return response
}
