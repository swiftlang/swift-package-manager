/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

extension Package {
    func shouldConsiderDirectory(path: String) -> Bool {
        let base = path.basename.lowercased()
        if base == "tests" { return false }
        if base.hasSuffix(".xcodeproj") { return false }
        if base.hasSuffix(".playground") { return false }
        if base.hasPrefix(".") { return false }  // eg .git
        if excludes.contains(path) { return false }
        if path.normpath == packagesDirectory.normpath { return false }
        if !path.isDirectory { return false }
        return true
    }

    var packagesDirectory: String {
        return Path.join(path, "Packages")
    }

    var excludes: [String] {
        return manifest.package.exclude.map{ Path.join(self.path, $0).normpath }
    }
}
