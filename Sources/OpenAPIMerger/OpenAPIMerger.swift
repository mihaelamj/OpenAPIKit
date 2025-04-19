import OpenAPIKit
import Yams
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAPIMerger {
    let baseURL: URL
    let isRemote: Bool
    
    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.isRemote = baseURL.scheme?.starts(with: "http") ?? false
    }
    
    public func mergeSpecification(completion: @escaping (Result<OpenAPI.Document, Error>) -> Void) {
        // 1. Create base document with info
        let info = OpenAPI.Document.Info(
            title: "Unified API Specification",
            description: "Combined API specification for all services", 
            version: "1.0.0"
        )
        
        // 2. Find all YAML files recursively with their paths
        findYAMLFiles(startingFrom: baseURL) { result in
            switch result {
            case .success(let yamlFiles):
                // 3. Load and merge all components and paths
                self.loadAndMergeFiles(yamlFiles) { result in
                    switch result {
                    case .success(let (components, paths, tags)):
                        // 4. Create unified document
                        let document = OpenAPI.Document(
                            openAPIVersion: .v3_1_0,
                            info: info,
                            servers: [], // Add servers as needed
                            paths: paths,
                            components: components,
                            security: [],
                            tags: tags,
                            externalDocs: nil
                        )
                        completion(.success(document))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func findYAMLFiles(startingFrom url: URL, completion: @escaping (Result<[(URL, [String])], Error>) -> Void) {
        if isRemote {
            findRemoteYAMLFiles(startingFrom: url, completion: completion)
        } else {
            findLocalYAMLFiles(startingFrom: url, completion: completion)
        }
    }
    
    private func findLocalYAMLFiles(startingFrom url: URL, pathComponents: [String] = [], completion: @escaping (Result<[(URL, [String])], Error>) -> Void) {
        var yamlFiles: [(URL, [String])] = []
        let fileManager = FileManager.default
        
        do {
            // Get directory contents
            let entries = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            let group = DispatchGroup()
            var errors: [Error] = []
            
            // Process each entry
            for entry in entries {
                let resourceValues = try entry.resourceValues(forKeys: [.isDirectoryKey])
                let currentPath = pathComponents + [entry.lastPathComponent]
                
                if resourceValues.isDirectory == true {
                    // Recursively search subdirectories
                    group.enter()
                    findLocalYAMLFiles(startingFrom: entry, pathComponents: currentPath) { result in
                        switch result {
                        case .success(let subFiles):
                            yamlFiles.append(contentsOf: subFiles)
                        case .failure(let error):
                            errors.append(error)
                        }
                        group.leave()
                    }
                } else if entry.pathExtension == "yml" || entry.pathExtension == "yaml" {
                    // Found a YAML file
                    yamlFiles.append((entry, currentPath))
                }
            }
            
            group.notify(queue: .main) {
                if let error = errors.first {
                    completion(.failure(error))
                } else {
                    completion(.success(yamlFiles))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func findRemoteYAMLFiles(startingFrom url: URL, pathComponents: [String] = [], completion: @escaping (Result<[(URL, [String])], Error>) -> Void) {
        var yamlFiles: [(URL, [String])] = []
        
        // Get directory listing
        fetchURLData(url) { result in
            switch result {
            case .success(let (data, response)):
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    completion(.failure(OpenAPIMergeError.invalidResponse(url: url)))
                    return
                }
                
                do {
                    // Parse directory listing (assuming JSON response)
                    let entries = try JSONDecoder().decode([DirectoryEntry].self, from: data)
                    
                    let group = DispatchGroup()
                    var errors: [Error] = []
                    
                    // Process entries
                    for entry in entries {
                        let currentPath = pathComponents + [entry.name]
                        if entry.isDirectory {
                            // Recursively search subdirectories
                            group.enter()
                            self.findRemoteYAMLFiles(
                                startingFrom: url.appendingPathComponent(entry.name),
                                pathComponents: currentPath
                            ) { result in
                                switch result {
                                case .success(let subFiles):
                                    yamlFiles.append(contentsOf: subFiles)
                                case .failure(let error):
                                    errors.append(error)
                                }
                                group.leave()
                            }
                        } else if entry.name.hasSuffix(".yml") || entry.name.hasSuffix(".yaml") {
                            // Found a YAML file
                            yamlFiles.append((url.appendingPathComponent(entry.name), currentPath))
                        }
                    }
                    
                    group.notify(queue: .main) {
                        if let error = errors.first {
                            completion(.failure(error))
                        } else {
                            completion(.success(yamlFiles))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func loadAndMergeFiles(_ yamlFiles: [(URL, [String])], completion: @escaping (Result<(OpenAPI.Components, OpenAPI.PathItem.Map, [OpenAPI.Tag]), Error>) -> Void) {
        var schemas = OrderedDictionary<OpenAPI.ComponentKey, JSONSchema>()
        var parameters = OrderedDictionary<OpenAPI.ComponentKey, OpenAPI.Parameter>()
        var responses = OrderedDictionary<OpenAPI.ComponentKey, OpenAPI.Response>()
        var examples = OrderedDictionary<OpenAPI.ComponentKey, OpenAPI.Example>()
        var paths = OpenAPI.PathItem.Map()
        var tags: [OpenAPI.Tag] = []
        var errors: [Error] = []
        
        let group = DispatchGroup()
        
        // Process files concurrently
        for (fileURL, pathComponents) in yamlFiles {
            group.enter()
            loadYAMLContent(from: fileURL) { result in
                switch result {
                case .success(let content):
                    // Create tag from directory structure
                    if pathComponents.count > 1 {
                        let tagName = pathComponents[pathComponents.count - 2]
                        let tag = OpenAPI.Tag(
                            name: tagName,
                            description: "APIs and components from the \(tagName) service",
                            externalDocs: nil
                        )
                        // Only add the tag if it's not already in the array
                        if !tags.contains(where: { $0.name == tagName }) {
                            tags.append(tag)
                        }
                    }
                    
                    // Try to parse as OpenAPI Document first
                    do {
                        if let doc = try? YAMLDecoder().decode(OpenAPI.Document.self, from: content) {
                            // Merge paths with directory-based tags
                            for (path, eitherPathItem) in doc.paths {
                                // Handle both reference and inline PathItems
                                let pathItem: OpenAPI.PathItem
                                switch eitherPathItem {
                                case .a(let reference):
                                    // Handle reference to PathItem
                                    guard let name = reference.name else {
                                        throw OpenAPIMergeError.invalidPathItem(url: fileURL)
                                    }
                                    guard let key = OpenAPI.ComponentKey(rawValue: name) else {
                                        throw OpenAPIMergeError.invalidPathItem(url: fileURL)
                                    }
                                    guard let referencedPathItem = doc.components.pathItems[key] else {
                                        throw OpenAPIMergeError.invalidPathItem(url: fileURL)
                                    }
                                    pathItem = referencedPathItem
                                case .b(let inlinePathItem):
                                    // Handle inline PathItem
                                    pathItem = inlinePathItem
                                }
                                
                                var taggedItem = pathItem
                                if pathComponents.count > 1 {
                                    let tagName = pathComponents[pathComponents.count - 2]
                                    
                                    // Helper function to create tagged operation
                                    func createTaggedOperation(_ operation: OpenAPI.Operation?) -> OpenAPI.Operation? {
                                        guard let operation = operation else { return nil }
                                        return OpenAPI.Operation(
                                            tags: [tagName],
                                            summary: operation.summary,
                                            description: operation.description,
                                            externalDocs: operation.externalDocs,
                                            operationId: operation.operationId,
                                            parameters: operation.parameters,
                                            requestBody: operation.requestBody ?? .b(OpenAPI.Request(description: nil, content: [:], required: false)),
                                            responses: operation.responses,
                                            callbacks: operation.callbacks,
                                            deprecated: operation.deprecated,
                                            security: operation.security,
                                            servers: operation.servers,
                                            vendorExtensions: operation.vendorExtensions
                                        )
                                    }
                                    
                                    // Add tags to all operations
                                    taggedItem.get = createTaggedOperation(taggedItem.get)
                                    taggedItem.put = createTaggedOperation(taggedItem.put)
                                    taggedItem.post = createTaggedOperation(taggedItem.post)
                                    taggedItem.delete = createTaggedOperation(taggedItem.delete)
                                    taggedItem.options = createTaggedOperation(taggedItem.options)
                                    taggedItem.head = createTaggedOperation(taggedItem.head)
                                    taggedItem.patch = createTaggedOperation(taggedItem.patch)
                                    taggedItem.trace = createTaggedOperation(taggedItem.trace)
                                }
                                paths[path] = .init(taggedItem)
                            }
                            
                            // Merge components with directory-based names
                            for (name, schema) in doc.components.schemas {
                                let prefixedName = pathComponents.count > 1 ? 
                                    "\(pathComponents[pathComponents.count - 2])_\(name.rawValue)" : name.rawValue
                                if let key = OpenAPI.ComponentKey(rawValue: prefixedName) {
                                    schemas[key] = schema
                                }
                            }
                            for (name, param) in doc.components.parameters {
                                let prefixedName = pathComponents.count > 1 ? 
                                    "\(pathComponents[pathComponents.count - 2])_\(name.rawValue)" : name.rawValue
                                if let key = OpenAPI.ComponentKey(rawValue: prefixedName) {
                                    parameters[key] = param
                                }
                            }
                            for (name, response) in doc.components.responses {
                                let prefixedName = pathComponents.count > 1 ? 
                                    "\(pathComponents[pathComponents.count - 2])_\(name.rawValue)" : name.rawValue
                                if let key = OpenAPI.ComponentKey(rawValue: prefixedName) {
                                    responses[key] = response
                                }
                            }
                            for (name, example) in doc.components.examples {
                                let prefixedName = pathComponents.count > 1 ? 
                                    "\(pathComponents[pathComponents.count - 2])_\(name.rawValue)" : name.rawValue
                                if let key = OpenAPI.ComponentKey(rawValue: prefixedName) {
                                    examples[key] = example
                                }
                            }
                        } else {
                            // Try to parse as individual component
                            let componentName = fileURL.deletingPathExtension().lastPathComponent
                            let prefixedName = pathComponents.count > 1 ? 
                                "\(pathComponents[pathComponents.count - 2])_\(componentName)" : componentName
                            
                            if let key = OpenAPI.ComponentKey(rawValue: prefixedName) {
                                if let schema = try? YAMLDecoder().decode(JSONSchema.self, from: content) {
                                    schemas[key] = schema
                                } else if let param = try? YAMLDecoder().decode(OpenAPI.Parameter.self, from: content) {
                                    parameters[key] = param
                                } else if let response = try? YAMLDecoder().decode(OpenAPI.Response.self, from: content) {
                                    responses[key] = response
                                }
                            }
                        }
                    } catch {
                        errors.append(error)
                    }
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if let error = errors.first {
                completion(.failure(error))
            } else {
                let components = OpenAPI.Components(
                    schemas: schemas,
                    responses: responses,
                    parameters: parameters,
                    examples: examples,
                    requestBodies: OrderedDictionary(),
                    headers: OrderedDictionary(),
                    securitySchemes: OrderedDictionary(),
                    links: OrderedDictionary(),
                    callbacks: OrderedDictionary()
                )
                completion(.success((components, paths, tags)))
            }
        }
    }
    
    private func loadYAMLContent(from url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        if isRemote {
            fetchURLData(url) { result in
                switch result {
                case .success(let (data, response)):
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        completion(.failure(OpenAPIMergeError.invalidResponse(url: url)))
                        return
                    }
                    completion(.success(String(decoding: data, as: UTF8.self)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                completion(.success(content))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func fetchURLData(_ url: URL, completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data, let response = response {
                completion(.success((data, response)))
            } else {
                completion(.failure(OpenAPIMergeError.invalidResponse(url: url)))
            }
        }
        task.resume()
    }
} 
