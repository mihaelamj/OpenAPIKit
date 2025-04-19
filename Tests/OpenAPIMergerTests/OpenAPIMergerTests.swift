import XCTest
import OpenAPIMerger
import OpenAPIKit
import Yams

final class OpenAPIMergerTests: XCTestCase {
    func testLocalMerging() async throws {
        // Get the path to the demospecs directory
        let currentFile = URL(fileURLWithPath: #file)
        let demospecsURL = currentFile
            .deletingLastPathComponent() // Tests/OpenAPIMergerTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("demospecs")
        
        let merger = OpenAPIMerger(baseURL: demospecsURL)
        let unifiedDoc = try await merger.mergeSpecification()
        
        // Basic validation
        XCTAssertNotNil(unifiedDoc)
        XCTAssertFalse(unifiedDoc.paths.isEmpty)
        XCTAssertNotNil(unifiedDoc.components.schemas)
        
        // Validate the document
        let warnings = try unifiedDoc.validate(strict: true)
        XCTAssertTrue(warnings.isEmpty, "Document validation failed with warnings: \(warnings)")
    }
    
    func testRemoteMerging() async throws {
        // This test would require a mock server or a real remote URL
        // For now, we'll skip it
        throw XCTSkip("Remote merging test requires a mock server or real remote URL")
    }
    
    func testErrorHandling() async throws {
        // Test with non-existent local directory
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path")
        let merger = OpenAPIMerger(baseURL: nonExistentURL)
        
        do {
            _ = try await merger.mergeSpecification()
            XCTFail("Expected error when merging from non-existent directory")
        } catch {
            XCTAssertTrue(error is OpenAPIMergeError)
        }
    }
} 