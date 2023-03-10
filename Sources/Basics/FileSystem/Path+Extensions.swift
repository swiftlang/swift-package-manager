//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.AbsolutePath

extension AbsolutePath {
    public func appending(_ component: String) -> AbsolutePath {
        self.appending(component: component)
    }

    public func appending(_ components: String...) -> AbsolutePath {
        self.appending(components: components)
    }

    public func appending(extension: String) -> AbsolutePath {
        guard !self.isRoot else { return self }
        let `extension` = `extension`.spm_dropPrefix(".")
        return self.parentDirectory.appending("\(basename).\(`extension`)")
    }

    public func basenameWithoutAnyExtension() -> String {
        var basename = self.basename
        if let index = basename.firstIndex(of: ".") {
            basename.removeSubrange(index ..< basename.endIndex)
        }
        return String(basename)
    }

    public func escapedPathString() -> String {
        return self.pathString.replacingOccurrences(of: "\\", with: "\\\\")
    }
}
