import Foundation

/// Typed errors for WarpLink SDK operations.
public enum WarpLinkError: Error, LocalizedError {
    /// SDK used before `configure()` was called.
    case notConfigured

    /// API key format is invalid (must be wl_live_ or wl_test_ + 32 alphanumeric chars).
    case invalidApiKeyFormat

    /// API key was rejected by the server.
    case invalidApiKey

    /// Network request failed with an underlying error.
    case networkError(Error)

    /// API returned an error response.
    case serverError(statusCode: Int, message: String)

    /// The URL is not a valid WarpLink Universal Link.
    case invalidURL

    /// The link was not found (404) or is no longer active.
    case linkNotFound

    /// Response parsing failed.
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "WarpLink SDK is not configured. Call WarpLink.configure(apiKey:) first."
        case .invalidApiKeyFormat:
            return "API key must start with 'wl_live_' or 'wl_test_' followed by 32 alphanumeric characters."
        case .invalidApiKey:
            return "The provided API key is invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidURL:
            return "The URL is not a valid WarpLink Universal Link."
        case .linkNotFound:
            return "The link was not found or is no longer active."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
