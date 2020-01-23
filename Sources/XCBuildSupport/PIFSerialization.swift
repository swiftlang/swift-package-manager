/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// This is used as part of the signature for the high-level PIF objects, to ensure that changes to the PIF schema are represented by the objects which do not use a content-based signature scheme (workspaces and projects, currently).
let pifEncodingSchemaVersion = 11

extension PIF.Project: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(signature, forKey: "signature")
        try container.encode("project", forKey: "type")

        var contents = container.nestedContainer(keyedBy: StringKey.self, forKey: "contents")
        try contents.encode(id, forKey: StringKey("guid"))
        try contents.encode(name, forKey: StringKey("projectName"))
        try contents.encode("true", forKey: StringKey("projectIsPackage"))
        try contents.encode(path, forKey: StringKey("path"))
        try contents.encode(projectDir, forKey: StringKey("projectDirectory"))
        try contents.encode("en", forKey: StringKey("developmentRegion"))
        try contents.encode(buildConfigs, forKey: StringKey("buildConfigurations"))
        try contents.encode("Release", forKey: StringKey("defaultConfigurationName"))
        try contents.encode(mainGroup, forKey: StringKey("groupTree"))
        try contents.encode(targets.map{ $0.signature }, forKey: StringKey("targets"))
    }
}

extension PIF.Group {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        try container.encode("group", forKey: StringKey("type"))
        try container.encode(id, forKey: StringKey("guid"))
        try container.encode(pathBase.asString, forKey: StringKey("sourceTree"))
        try container.encode(path, forKey: StringKey("path"))
        try container.encode(name ?? path, forKey: StringKey("name"))
        try container.encode(subitems, forKey: StringKey("children"))
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
            return
                pathExtension.flatMap { pathExtension in
                    XCBuildFileType.all.first { $0.fileTypes.contains(pathExtension) }
                }?.fileTypeIdentifier ?? "file"
        }
    }

    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        try container.encode("file", forKey: StringKey("type"))
        try container.encode(id, forKey: StringKey("guid"))
        try container.encode(pathBase.asString, forKey: StringKey("sourceTree"))
        try container.encode(path, forKey: StringKey("path"))
        try container.encode(
            fileType ?? fileTypeIdentifier(for: path),
            forKey: StringKey("fileType")
        )
    }
}

extension PIF.AggregateTarget {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        try container.encode("aggregate", forKey: StringKey("type"))
        try container.encode(id, forKey: StringKey("guid"))
        try container.encode(name, forKey: StringKey("name"))
        try container.encode(
            dependencies.map { ["guid": $0.targetId] },
            forKey: StringKey("dependencies")
        )
        try container.encode(buildPhases, forKey: StringKey("buildPhases"))
        try container.encode(buildConfigs, forKey: StringKey("buildConfigurations"))
        try container.encode(impartedBuildProperties, forKey: StringKey("impartedBuildProperties"))
    }
}

extension PIF.Target {
    func _encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(signature, forKey: "signature")
        try container.encode("target", forKey: "type")

        var contents = container.nestedContainer(keyedBy: StringKey.self, forKey: "contents")

        if productType == .packageProduct {
            try contents.encode("packageProduct", forKey: StringKey("type"))
            try contents.encode(id, forKey: StringKey("guid"))
            try contents.encode(name, forKey: StringKey("name"))
            try contents.encode(
                dependencies.map { ["guid": $0.targetId] },
                forKey: StringKey("dependencies")
            )
            try contents.encode(buildConfigs, forKey: StringKey("buildConfigurations"))

            // Add the framework build phase, if present.
            if let phase = buildPhases.first as? PIF.FrameworksBuildPhase {
                try contents.encode(phase, forKey: StringKey("frameworksBuildPhase"))
            }
            return
        }

        try contents.encode("standard", forKey: StringKey("type"))
        try contents.encode(id, forKey: StringKey("guid"))
        try contents.encode(name, forKey: StringKey("name"))
        try contents.encode(
            dependencies.map { ["guid": $0.targetId] },
            forKey: StringKey("dependencies")
        )

        try contents.encode(productType.asString, forKey: StringKey("productTypeIdentifier"))

        let productReference = [
            "type": "file",
            "guid": "PRODUCTREF-\(id)",
            "name": productName,
        ]
        try contents.encode(productReference, forKey: StringKey("productReference"))

        try contents.encode([String](), forKey: StringKey("buildRules"))
        try contents.encode(buildPhases, forKey: StringKey("buildPhases"))
        try contents.encode(buildConfigs, forKey: StringKey("buildConfigurations"))
        try contents.encode(impartedBuildProperties, forKey: StringKey("impartedBuildProperties"))
    }
}

extension PIF.BuildPhase: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        try container.encode(Swift.type(of: self).type, forKey: StringKey("type"))
        try container.encode(id, forKey: StringKey("guid"))
        try container.encode(files, forKey: StringKey("buildFiles"))
    }
}

extension PIF.BuildFile: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        try container.encode(id, forKey: StringKey("guid"))

        switch self.ref {
        case .reference(let refId):
            try container.encode(refId, forKey: StringKey("fileReference"))
        case .targetProduct(let refId):
            try container.encode(refId, forKey: StringKey("targetReference"))
        }
    }
}

extension PIF.BuildConfig: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)

        try container.encode(id, forKey: StringKey("guid"))
        try container.encode(name, forKey: StringKey("name"))
        try container.encode(settings, forKey: StringKey("buildSettings"))
    }
}

extension PIF.ImpartedBuildProperties: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringKey.self)
        try container.encode(settings, forKey: StringKey("buildSettings"))
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
                    try container.encode(value, forKey: StringKey("\(key.rawValue)[\(condition)]"))
                }
            }
        }
    }
}

struct StringKey: CodingKey, ExpressibleByStringLiteral {

    var stringValue: String

    init(stringLiteral stringValue: String) {
        self.stringValue = stringValue
    }

    init(stringValue value: String) {
        self.stringValue = value
    }

    init(_ value: String) {
        self.stringValue = value
    }

    var intValue: Int?
    init?(intValue: Int) {
        fatalError()
    }
}
