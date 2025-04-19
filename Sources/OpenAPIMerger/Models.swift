import Foundation

// Model for remote directory listing
struct DirectoryEntry: Codable {
    let name: String
    let isDirectory: Bool
    let size: Int?
    let modified: Date?
}

public enum OpenAPIMergeError: Error {
    case invalidResponse(url: URL)
    case invalidDirectoryListing(url: URL)
    case invalidYAML(url: URL, error: Error)
    case fileNotFound(url: URL)
    case invalidPathItem(url: URL)
    
    public var localizedDescription: String {
        switch self {
        case .invalidResponse(let url):
            return "Invalid response from URL: \(url.absoluteString)"
        case .invalidDirectoryListing(let url):
            return "Invalid directory listing from URL: \(url.absoluteString)"
        case .invalidYAML(let url, let error):
            return "Invalid YAML at URL: \(url.absoluteString). Error: \(error.localizedDescription)"
        case .fileNotFound(let url):
            return "File not found at URL: \(url.absoluteString)"
        case .invalidPathItem(let url):
            return "Invalid path item in OpenAPI document at URL: \(url.absoluteString)"
        }
    }
} 