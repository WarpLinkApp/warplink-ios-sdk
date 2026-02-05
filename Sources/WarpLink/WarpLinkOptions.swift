import Foundation

/// Configuration options for the WarpLink SDK.
public struct WarpLinkOptions: Sendable {
    /// The API endpoint URL.
    public let apiEndpoint: String

    /// Whether to enable debug logging.
    public let debugLogging: Bool

    /// The match window in hours for deferred deep link attribution.
    public let matchWindowHours: Int

    public init(
        apiEndpoint: String = "https://api.warplink.app/v1",
        debugLogging: Bool = false,
        matchWindowHours: Int = 72
    ) {
        self.apiEndpoint = apiEndpoint
        self.debugLogging = debugLogging
        self.matchWindowHours = matchWindowHours
    }
}
