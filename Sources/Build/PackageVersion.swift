/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import PackageType
import class Utility.Git
import struct Utility.Path
import func libc.fclose

public func generateVersionData(_ rootDir: String, rootPackage: Package, externalPackages: [Package]) throws {
    let dirPath = Path.join(rootDir, ".build/versionData")
    try mkdir(dirPath)

    try saveRootPackage(dirPath, package: rootPackage)
    for (pkgName, data) in generateData(externalPackages) {
        try saveVersionData(dirPath, packageName: pkgName, data: data)
    }
}

func saveRootPackage(_ dirPath: String, package: Package) throws {
    guard let repo = Git.Repo(path: package.path),
        headSha = repo.sha,
        version = package.version else { return }

    let prefix = repo.versionsArePrefixed ? "v" : ""
    let versionSha = try repo.versionSha(tag: "\(prefix)\(version)")

    var data = packageVersionData(package)
    if headSha != versionSha {
        data += "public let sha: String = \"\(headSha)\" \n"
    }
    if repo.hasLocalChanges {
        //TODO: save time
        data += "public let modified: String = \"\" \n"
    }

    try saveVersionData(dirPath, packageName: package.name, data: data)
}

func generateData(_ packages: [Package]) -> [String : String] {
    var versionData = [String : String]()
    for pkg in packages {
        versionData[pkg.name] = packageVersionData(pkg)
    }
    return versionData
}

func packageVersionData(_ package: Package) -> String {
    var data = "public let url: String = \"\(package.url)\" \n" +
        "public let version: (Int, Int, Int, [String], String?)?"
    if let version = package.version {
        data += " = \(version.major, version.minor, version.patch, version.prereleaseIdentifiers, version.buildMetadataIdentifier) \n"
    }
    return data
}

private func saveVersionData(_ dirPath: String, packageName: String, data: String) throws {
    let filePath = Path.join(dirPath, "\(packageName).swift")
    let file = try fopen(filePath, mode: .Write)
    defer {
        libc.fclose(file)
    }
    try fputs(data, file)
}
