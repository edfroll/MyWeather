import Foundation

/// The app wraps the system networking session in its own transport type (MW-48) — not an extension of that
/// session: `data(for:)` would overload its own method by return type and call itself. Tests use a stub.
/// No system session in this package (A-20).
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
