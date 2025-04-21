//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import OrderedCollections
import PackageModel

import struct TSCBasic.ByteString

#if canImport(SwiftBuild)
import enum SwiftBuild.ProjectModel

/// The Project Interchange Format (PIF) is a structured representation of the
/// project model created by clients to send to SwiftBuild.
///
/// The PIF is a representation of the project model describing the static
/// objects which contribute to building products from the project, independent
/// of "how" the user has chosen to build those products in any particular
/// build. This information can be cached by SwiftBuild between builds (even
/// between builds which use different schemes or configurations), and can be
/// incrementally updated by clients when something changes.
public enum PIF {
    /// The type used for identifying PIF objects.
    public typealias GUID = ProjectModel.GUID
    
    /// The top-level PIF object.
    public struct TopLevelObject: Encodable {
        public let workspace: PIF.Workspace
        
        public init(workspace: PIF.Workspace) {
            self.workspace = workspace
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            
            // Encode the workspace.
            try container.encode(workspace)
            
            // Encode the projects and their targets.
            for project in workspace.projects {
                try container.encode(project)
                let targets = project.underlying.targets
                
                for target in targets where !target.id.hasSuffix(.dynamic) {
                    try container.encode(Target(wrapping: target))
                }
                
                // Add *dynamic variants* at the end just to have a clear split from other targets.
                for target in targets where target.id.hasSuffix(.dynamic) {
                    try container.encode(Target(wrapping: target))
                }
            }
        }
    }
    
    /// Represents a high-level PIF object.
    ///
    /// For instance, a JSON serialized *workspace* might look like this:
    /// ```json
    /// {
    ///     "type" : "workspace",
    ///     "signature" : "22e9436958aec481799",
    ///     "contents" : {
    ///         "guid" : "Workspace:/Users/foo/BarPackage",
    ///         "name" : "BarPackage",
    ///         "path" : "/Users/foo/BarPackage",
    ///         "projects" : [
    ///             "70a588f37dcfcddbc1f",
    ///             "c1d9cb257bd42cafbb8"
    ///         ]
    ///     }
    /// }
    /// ```
    public class HighLevelObject: Codable {
        class var type: String {
            fatalError("\(self) missing implementation")
        }
        
        let type: String
        
        fileprivate init() {
            type = Self.type
        }
        
        fileprivate enum CodingKeys: CodingKey {
            case type
            case signature, contents // Used by subclasses.
        }
        
        public func encode(to encoder: Encoder) throws {
            var superContainer = encoder.container(keyedBy: CodingKeys.self)
            try superContainer.encode(type, forKey: .type)
        }
        
        required public init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try superContainer.decode(String.self, forKey: .type)
            
            guard self.type == Self.type else {
                throw InternalError("Expected same type for high-level object: \(self.type)")
            }
        }
    }
    
    /// The high-level PIF *workspace* object.
    public final class Workspace: HighLevelObject {
        override class var type: String { "workspace" }
        
        public let guid: GUID
        public var name: String
        public var path: AbsolutePath
        public var projects: [Project]
        var signature: String?

        public init(guid: GUID, name: String, path: AbsolutePath, projects: [ProjectModel.Project]) {
            precondition(!guid.value.isEmpty)
            precondition(!name.isEmpty)
            precondition(Set(projects.map(\.id)).count == projects.count)
            
            self.guid = guid
            self.name = name
            self.path = path
            self.projects = projects.map { Project(wrapping: $0) }
            super.init()
        }
        
        private enum CodingKeys: CodingKey {
            case guid, name, path, projects
        }
        
        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            
            var superContainer = encoder.container(keyedBy: HighLevelObject.CodingKeys.self)
            var contents = superContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .contents)
            
            try contents.encode("\(guid)", forKey: .guid)
            try contents.encode(name, forKey: .name)
            try contents.encode(path, forKey: .path)
            try contents.encode(projects.map(\.signature), forKey: .projects)
            
            if encoder.userInfo.keys.contains(.encodeForSwiftBuild) {
                guard let signature else {
                    throw InternalError("Expected to have workspace *signature* when encoding for SwiftBuild")
                }
                try superContainer.encode(signature, forKey: .signature)
            }
        }
        
        public required init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: HighLevelObject.CodingKeys.self)
            let contents = try superContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .contents)
            
            self.guid = try contents.decode(GUID.self, forKey: .guid)
            self.name = try contents.decode(String.self, forKey: .name)
            self.path = try contents.decode(AbsolutePath.self, forKey: .path)
            self.projects = try contents.decode([Project].self, forKey: .projects)
            
            try super.init(from: decoder)
        }
    }
    
    /// A high-level PIF *project* object.
    public final class Project: HighLevelObject {
        override class var type: String { "project" }
        
        public var underlying: ProjectModel.Project
        var signature: String?
        var id: ProjectModel.GUID { underlying.id }
        
        public init(wrapping underlying: ProjectModel.Project) {
            precondition(!underlying.name.isEmpty)
            precondition(!underlying.id.value.isEmpty)
            precondition(!underlying.path.isEmpty)
            precondition(!underlying.projectDir.isEmpty)
            
            precondition(Set(underlying.targets.map(\.id)).count == underlying.targets.count)
            precondition(Set(underlying.buildConfigs.map(\.id)).count == underlying.buildConfigs.count)
            
            self.underlying = underlying
            super.init()
        }
        
        public override func encode(to encoder: any Encoder) throws {
            try super.encode(to: encoder)
            var superContainer = encoder.container(keyedBy: HighLevelObject.CodingKeys.self)
            try superContainer.encode(underlying, forKey: .contents)

            if encoder.userInfo.keys.contains(.encodeForSwiftBuild) {
                guard let signature else {
                    throw InternalError("Expected to have project *signature* when encoding for SwiftBuild")
                }
                try superContainer.encode(signature, forKey: .signature)
            }
        }
        
        public required init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: HighLevelObject.CodingKeys.self)
            self.underlying = try superContainer.decode(ProjectModel.Project.self, forKey: .contents)
            
            try super.init(from: decoder)
        }
    }
    
    /// A high-level PIF *target* object.
    private final class Target: HighLevelObject {
        override class var type: String { "target" }
        
        public var underlying: ProjectModel.BaseTarget
        var id: ProjectModel.GUID { underlying.id }
        
        public init(wrapping underlying: ProjectModel.BaseTarget) {
            precondition(!underlying.id.value.isEmpty)
            precondition(!underlying.common.name.isEmpty)
            
            self.underlying = underlying
            super.init()
        }
        
        public override func encode(to encoder: any Encoder) throws {
            try super.encode(to: encoder)
            var superContainer = encoder.container(keyedBy: HighLevelObject.CodingKeys.self)
            try superContainer.encode(underlying, forKey: .contents)

            if encoder.userInfo.keys.contains(.encodeForSwiftBuild) {
                guard let signature = underlying.common.signature else {
                    throw InternalError("Expected to have target *signature* when encoding for SwiftBuild")
                }
                try superContainer.encode(signature, forKey: .signature)
            }
        }
        
        public required init(from decoder: Decoder) throws {
            // FIXME: Remove all support for decoding PIF objects in SwiftBuildSupport? rdar://149003797
            fatalError("Decoding not implemented")
            /*
            let superContainer = try decoder.container(keyedBy: HighLevelObject.CodingKeys.self)
            self.underlying = try superContainer.decode(ProjectModel.BaseTarget.self, forKey: .contents)
            
            try super.init(from: decoder)
            */
        }
    }
}

// MARK: - PIF Signature Support

extension CodingUserInfoKey {
    /// Perform the encoding for SwiftBuild consumption.
    public static let encodeForSwiftBuild: CodingUserInfoKey = CodingUserInfoKey(rawValue: "encodeForXCBuild")!
}

extension PIF {
    /// Add signature to workspace and its high-level subobjects.
    static func sign(workspace: PIF.Workspace) throws {
        let encoder = JSONEncoder.makeWithDefaults()

        func signature(of obj: some Encodable) throws -> String {
            let signatureContent = try encoder.encode(obj)
            let signatureBytes = ByteString(signatureContent)
            let signature = signatureBytes.sha256Checksum
            return signature
        }

        for project in workspace.projects {
            for targetIndex in project.underlying.targets.indices {
                let targetSignature = try signature(of: project.underlying.targets[targetIndex])
                project.underlying.targets[targetIndex].common.signature = targetSignature
            }
            project.signature = try signature(of: project)
        }
        workspace.signature = try signature(of: workspace)
    }
}

#endif // SwiftBuild
