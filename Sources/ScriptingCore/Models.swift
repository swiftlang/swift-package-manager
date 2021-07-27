//
//  File.swift
//  File
//
//  Created by C YR on 2021/7/19.
//

import Foundation
import TSCBasic
import TSCUtility

public struct PackageModel: Codable {
    public let raw: String
    public let url: Foundation.URL?
    public let path: AbsolutePath?
    public let _name: String?

    public var name: String {
        if let name = _name {
            return name
        }
        let name: String
        if let path = path {
            name = path.basename
        } else if let url = url {
            name = url.pathComponents.last!.spm_dropGitSuffix()
        } else {
            fatalError()
        }
        return name
    }
}

public struct PackageDependency: Codable {
    public let package: PackageModel
    public var modules: [String] = []
    
    init(of package: PackageModel) {
        self.package = package
    }
}

public struct ScriptDependencies: Codable {
    public let sourceFile: AbsolutePath
    public let modules: [PackageDependency]
}

public extension PackageModel {
    enum CodingKeys: String, CodingKey {
        case raw
        case url
        case path
        case _name = "name"
    }
}
