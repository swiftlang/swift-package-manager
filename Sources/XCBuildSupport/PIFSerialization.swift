/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Foundation

/// This is used as part of the signature for the high-level PIF objects, to ensure that changes to the PIF schema are
/// represented by the objects which do not use a content-based signature scheme (workspaces and projects, currently).
let pifEncodingSchemaVersion = 11

extension PIF.TopLevelObject: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        // Encode the workspace.
        try container.encode(workspace)

        // Encode the projects and their targets.
        for project in workspace.projects {
            try container.encode(project)

            for target in project.targets {
                try container.encode(target)
            }
        }
    }
}

extension PIF.Workspace: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(signature, forKey: "signature")
        try container.encode("workspace", forKey: "type")

        var contents = container.nestedContainer(keyedBy: StringKey.self, forKey: "contents")
        try contents.encode(guid, forKey: "guid")
        try contents.encode(path, forKey: "path")
        try contents.encode(name, forKey: "name")
        try contents.encode(projects.map({ $0.signature }), forKey: "projects")
    }
}

extension PIF.Project: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(signature, forKey: "signature")
        try container.encode("project", forKey: "type")

        var contents = container.nestedContainer(keyedBy: StringKey.self, forKey: "contents")
        try contents.encode(id, forKey: "guid")
        try contents.encode(name, forKey: "projectName")
        try contents.encode("true", forKey: "projectIsPackage")
        try contents.encode(path, forKey: "path")
        try contents.encode(projectDir, forKey: "projectDirectory")
        // TODO: Replace by developmentRegion once localization implementation is merged.
        try contents.encode("en", forKey: "developmentRegion")
        try contents.encode(buildConfigs, forKey: "buildConfigurations")
        try contents.encode("Release", forKey: "defaultConfigurationName")
        try contents.encode(mainGroup, forKey: "groupTree")
        try contents.encode(targets.map({ $0.signature }), forKey: "targets")
    }
}

extension PIF.Group {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode("group", forKey: "type")
        try container.encode(id, forKey: "guid")
        try container.encode(pathBase.asString, forKey: "sourceTree")
        try container.encode(path, forKey: "path")
        try container.encode(name ?? path, forKey: "name")
        try container.encode(subitems, forKey: "children")
    }
}

extension PIF.FileReference {

    private func fileTypeIdentifier(for path: String) -> String {
        let pathExtension: String?
        if let path = try? AbsolutePath(validating: path) {
            pathExtension = path.extension
        } else if let path = try? RelativePath(validating: path) {
            pathExtension = path.extension
        } else {
            pathExtension = nil
        }

        switch pathExtension {
        case "a":
            return "archive.ar"
        case "s", "S":
            return "sourcecode.asm"
        case "c":
            return "sourcecode.c.c"
        case "cl":
            return "sourcecode.opencl"
        case "cpp", "cp", "cxx", "cc", "c++", "C", "tcc":
            return "sourcecode.cpp.cpp"
        case "d":
            return "sourcecode.dtrace"
        case "defs", "mig":
            return "sourcecode.mig"
        case "m":
            return "sourcecode.c.objc"
        case "mm", "M":
            return "sourcecode.cpp.objcpp"
        case "metal":
            return "sourcecode.metal"
        case "l", "lm", "lmm", "lpp", "lp", "lxx":
            return "sourcecode.lex"
        case "swift":
            return "sourcecode.swift"
        case "y", "ym", "ymm", "ypp", "yp", "yxx":
            return "sourcecode.yacc"

        case "xcassets":
            return "folder.assetcatalog"
        case "storyboard":
            return "file.storyboard"
        case "xib":
            return "file.xib"

        case "xcframework":
            return "wrapper.xcframework"

        default:
            return pathExtension.flatMap({ pathExtension in
                XCBuildFileType.allCases.first(where:{ $0.fileTypes.contains(pathExtension) })
            })?.fileTypeIdentifier ?? "file"
        }
    }

    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode("file", forKey: "type")
        try container.encode(id, forKey: "guid")
        try container.encode(pathBase.asString, forKey: "sourceTree")
        try container.encode(path, forKey: "path")
        try container.encode(fileType ?? fileTypeIdentifier(for: path), forKey: "fileType")
    }
}

extension PIF.AggregateTarget {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode("aggregate", forKey: "type")
        try container.encode(id, forKey: "guid")
        try container.encode(name, forKey: "name")
        try container.encode(dependencies.map({ ["guid": $0.targetId] }), forKey: "dependencies")
        try container.encode(buildPhases, forKey: "buildPhases")
        try container.encode(buildConfigs, forKey: "buildConfigurations")
        try container.encode(impartedBuildProperties, forKey: "impartedBuildProperties")
    }
}

extension PIF.Target {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(signature, forKey: "signature")
        try container.encode("target", forKey: "type")

        var contents = container.nestedContainer(keyedBy: StringKey.self, forKey: "contents")

        if productType == .packageProduct {
            try contents.encode("packageProduct", forKey: "type")
            try contents.encode(id, forKey: "guid")
            try contents.encode(name, forKey: "name")
            try contents.encode(dependencies.map({ ["guid": $0.targetId] }), forKey: "dependencies")
            try contents.encode(buildConfigs, forKey: "buildConfigurations")

            // Add the framework build phase, if present.
            if let phase = buildPhases.first as? PIF.FrameworksBuildPhase {
                try contents.encode(phase, forKey: "frameworksBuildPhase")
            }

            return
        }

        try contents.encode("standard", forKey: "type")
        try contents.encode(id, forKey: "guid")
        try contents.encode(name, forKey: "name")
        try contents.encode(dependencies.map({ ["guid": $0.targetId] }), forKey: "dependencies")
        try contents.encode(productType.asString, forKey: "productTypeIdentifier")

        let productReference = [
            "type": "file",
            "guid": "PRODUCTREF-\(id)",
            "name": productName,
        ]
        try contents.encode(productReference, forKey: "productReference")

        try contents.encode([String](), forKey: "buildRules")
        try contents.encode(buildPhases, forKey: "buildPhases")
        try contents.encode(buildConfigs, forKey: "buildConfigurations")
        try contents.encode(impartedBuildProperties, forKey: "impartedBuildProperties")
    }
}

extension PIF.BuildPhase: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(Swift.type(of: self).type, forKey: "type")
        try container.encode(id, forKey: "guid")
        try container.encode(files, forKey: "buildFiles")
    }
}

extension PIF.BuildFile: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(id, forKey: "guid")

        switch self.ref {
        case .reference(let refId):
            try container.encode(refId, forKey: "fileReference")
        case .targetProduct(let refId):
            try container.encode(refId, forKey: "targetReference")
        }
    }
}

extension PIF.BuildConfig: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(id, forKey: "guid")
        try container.encode(name, forKey: "name")
        try container.encode(settings, forKey: "buildSettings")
    }
}

extension PIF.ImpartedBuildProperties: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(settings, forKey: "buildSettings")
    }
}

extension PIF.BuildSettings: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            guard let name = child.label else {
                preconditionFailure("unnamed build settings are not supported")
            }
            switch child.value {
            case nil:
                continue
            case let value as String:
                try container.encode(value, forKey: StringKey(name))
            case let value as [String]:
                try container.encode(value, forKey: StringKey(name))
            default:
                continue
            }
        }

        for (platformCondition, values) in platformSpecificSettings {
            for condition in platformCondition.asConditionStrings {
                for (key, value) in values {
                    // If `$(inherited)` is the only value, do not emit anything to the PIF.
                    if value == ["$(inherited)"] {
                        return
                    }
                    try container.encode(value, forKey: "\(key.rawValue)[\(condition)]")
                }
            }
        }
    }
}

struct StringKey: CodingKey, ExpressibleByStringInterpolation {
    var stringValue: String
    var intValue: Int?

    init(stringLiteral stringValue: String) {
        self.stringValue = stringValue
    }

    init(stringValue value: String) {
        self.stringValue = value
    }

    init(_ value: String) {
        self.stringValue = value
    }

    init?(intValue: Int) {
        fatalError("does not support integer keys")
    }
}
