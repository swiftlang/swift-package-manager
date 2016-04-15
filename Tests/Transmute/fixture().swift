/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Path
import func POSIX.mkdir
import func POSIX.system
import func Utility.rmtree

func fixture(files: [String]) throws -> String {
    let testdir = Path.join(#file, "../../../.build/test.out").normpath
    if testdir.isDirectory {
        try rmtree(testdir)
    }
    try mkdir(testdir)
    for file in files {
        try system("touch", Path.join(testdir, file))
    }
    return testdir
}


@testable import Transmute
import PackageDescription
import PackageType

private var index = 0

func fixture(files: [String]) throws -> (PackageType.Package, [Module]) {
    index += 1

    let prefix: String = try fixture(files: files)
    let manifest = Manifest(path: Path.join(prefix, "Package.swift"), package: Package(name: "name\(index)"), products: [])
    let package = Package(manifest: manifest, url: prefix)
    let modules = try package.modules()
    return (package, modules)
}
