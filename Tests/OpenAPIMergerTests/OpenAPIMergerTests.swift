import XCTest
import OpenAPIMerger
import OpenAPIKit
import Yams

final class OpenAPIMergerTests: XCTestCase {
    var demospecsURL: URL!
    var merger: OpenAPIMerger!
    
    override func setUp() {
        let currentFile = URL(fileURLWithPath: #file)
        demospecsURL = currentFile
            .deletingLastPathComponent() // Tests/OpenAPIMergerTests
            .appendingPathComponent("demospecs")
        merger = OpenAPIMerger(baseURL: demospecsURL)
    }
    
    func testLocalMerging() throws {
        let expectation = XCTestExpectation(description: "Merge specification")
        var unifiedDoc: OpenAPI.Document?
        var mergeError: Error?
        
        merger.mergeSpecification { result in
            switch result {
            case .success(let doc):
                unifiedDoc = doc
            case .failure(let error):
                mergeError = error
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        if let error = mergeError {
            throw error
        }
        
        guard let doc = unifiedDoc else {
            XCTFail("No document returned")
            return
        }
        
        // Basic validation
        XCTAssertNotNil(doc)
        XCTAssertFalse(doc.paths.isEmpty)
        XCTAssertNotNil(doc.components.schemas)
        
        // Validate the document
        let warnings = try doc.validate(strict: true)
        XCTAssertTrue(warnings.isEmpty, "Document validation failed with warnings: \(warnings)")
    }
    
    func testComponentMerging() throws {
        let expectation = XCTestExpectation(description: "Merge specification")
        var unifiedDoc: OpenAPI.Document?
        var mergeError: Error?
        
        merger.mergeSpecification { result in
            switch result {
            case .success(let doc):
                unifiedDoc = doc
            case .failure(let error):
                mergeError = error
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        if let error = mergeError {
            throw error
        }
        
        guard let doc = unifiedDoc else {
            XCTFail("No document returned")
            return
        }
        
        // Test that components are merged with directory prefixes
        let schemaKeys = doc.components.schemas.keys
        XCTAssertFalse(schemaKeys.isEmpty)
        
        // Verify that at least some components have directory prefixes
        let hasPrefixedComponents = schemaKeys.contains { key in
            key.rawValue.contains(".")
        }
        XCTAssertTrue(hasPrefixedComponents, "No components found with directory prefixes")
        
        // Test that responses and parameters are merged
        XCTAssertFalse(doc.components.responses.isEmpty)
        XCTAssertFalse(doc.components.parameters.isEmpty)
    }
    
    func testPathMerging() throws {
        let expectation = XCTestExpectation(description: "Merge specification")
        var unifiedDoc: OpenAPI.Document?
        var mergeError: Error?
        
        merger.mergeSpecification { result in
            switch result {
            case .success(let doc):
                unifiedDoc = doc
            case .failure(let error):
                mergeError = error
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        if let error = mergeError {
            throw error
        }
        
        guard let doc = unifiedDoc else {
            XCTFail("No document returned")
            return
        }
        
        // Test that paths are merged
        XCTAssertFalse(doc.paths.isEmpty)
        
        // Test that path operations have tags
        var hasTaggedOperations = false
        for (_, eitherPathItem) in doc.paths {
            switch eitherPathItem {
            case .a(let reference):
                // Skip references for now
                continue
            case .b(let pathItem):
                // Check each operation for tags
                if let get = pathItem.get, !(get.tags?.isEmpty ?? true) {
                    hasTaggedOperations = true
                    break
                }
                if let post = pathItem.post, !(post.tags?.isEmpty ?? true) {
                    hasTaggedOperations = true
                    break
                }
                if let put = pathItem.put, !(put.tags?.isEmpty ?? true) {
                    hasTaggedOperations = true
                    break
                }
                if let delete = pathItem.delete, !(delete.tags?.isEmpty ?? true) {
                    hasTaggedOperations = true
                    break
                }
            }
        }
        XCTAssertTrue(hasTaggedOperations, "No path operations found with tags")
    }
    
    func testTagMerging() throws {
        let expectation = XCTestExpectation(description: "Merge specification")
        var unifiedDoc: OpenAPI.Document?
        var mergeError: Error?
        
        merger.mergeSpecification { result in
            switch result {
            case .success(let doc):
                unifiedDoc = doc
            case .failure(let error):
                mergeError = error
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        if let error = mergeError {
            throw error
        }
        
        guard let doc = unifiedDoc else {
            XCTFail("No document returned")
            return
        }
        
        // Test that tags are created
        guard let tags = doc.tags else {
            XCTFail("No tags found in document")
            return
        }
        XCTAssertFalse(tags.isEmpty)
        
        // Test that tags have descriptions
        let hasDescriptions = tags.contains { tag in
            tag.description != nil
        }
        XCTAssertTrue(hasDescriptions, "No tags found with descriptions")
    }
    
    func testRemoteMerging() throws {
        // This test would require a mock server or a real remote URL
        // For now, we'll skip it
        throw XCTSkip("Remote merging test requires a mock server or real remote URL")
    }
    
    func testErrorHandling() throws {
        // Test with non-existent local directory
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path")
        let merger = OpenAPIMerger(baseURL: nonExistentURL)
        
        let expectation = XCTestExpectation(description: "Merge specification")
        var mergeError: Error?
        
        merger.mergeSpecification { result in
            switch result {
            case .success:
                XCTFail("Expected error when merging from non-existent directory")
            case .failure(let error):
                mergeError = error
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        XCTAssertTrue(mergeError is OpenAPIMergeError)
    }
} 