/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel

import class Utility.Git

public func generateVersionData(_ rootDir: AbsolutePath, rootPackage: Package, externalPackages: [Package]) throws {
    let dirPath = rootDir.appending(components: ".build", "versionData")
    try localFileSystem.createDirectory(dirPath, recursive: true)

    try saveRootPackage(dirPath, package: rootPackage)
    for (pkgName, data) in generateData(externalPackages) {
        try saveVersionData(dirPath, packageName: pkgName, data: data)
    }
}

func saveRootPackage(_ dirPath: AbsolutePath, package: Package) throws {
    guard let repo = Git.Repo(path: package.path) else { return }
    var data = versionData(package: package)
    data += "public let sha: String? = "

    if let version = package.version {
        let prefix = repo.versionsArePrefixed ? "v" : ""
        let versionSha = try repo.versionSha(tag: "\(prefix)\(version)")

        if repo.sha != versionSha {
            data += "\"\(repo.sha)\"\n"
        } else {
            data += "nil\n"
        }
    } else {
        data += "\"\(repo.sha)\"\n"
    }

    data += "public let modified: Bool = "
    data += repo.hasLocalChanges ? "true" : "false"
    data += "\n"

    try saveVersionData(dirPath, packageName: package.name, data: data)
}

func generateData(_ packages: [Package]) -> [String : String] {
    var data = [String : String]()
    for pkg in packages {
        data[pkg.name] = versionData(package: pkg)
    }
    return data
}

func versionData(package: Package) -> String {
    var data = "public let url: String = \"\(package.url)\"\n"
    data += "public let version: (major: Int, minor: Int, patch: Int, prereleaseIdentifiers: [String], buildMetadata: String?) = "
    if let version = package.version {
        data += "\(version.major, version.minor, version.patch, version.prereleaseIdentifiers, version.buildMetadataIdentifier)\n"
        data += "public let versionString: String = \"\(version)\"\n"
    } else {
        data += "(0, 0, 0, [], nil) \n"
        data += "public let versionString: String = \"0.0.0\"\n"
    }

    return data
}

private func saveVersionData(_ dirPath: AbsolutePath, packageName: String, data: String) throws {
    let filePath = dirPath.appending(components: packageName + ".swift")
    try localFileSystem.writeFileContents(filePath, bytes: ByteString(encodingAsUTF8: data))
}
