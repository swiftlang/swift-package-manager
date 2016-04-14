/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.exit
import PackageType
import Utility
import POSIX

public class Options {
    public var chdir: String?
    public var path = Path()

    public class Path {
        public lazy var root = getroot()
        public var Packages: String { return Utility.Path.join(self.root) }

        public var build: String {
            get { return _build ?? Utility.Path.join(getroot(), ".build") }
            set { _build = newValue }
        }

        private var _build = getenv("SWIFT_BUILD_PATH")
    }

    public init()
    {}
}

public struct Flag {
    public static let chdir = "--chdir"
    public static let C = "-C"
}

private func getroot() -> String {
    var root = getcwd()
    while !Path.join(root, Manifest.filename).isFile {
        root = root.parentDirectory

        guard root != "/" else {
            // abort because lazy properties cannot throw and we
            // want erroring on no manifest found to be “lazy” so
            // any path that requires this property errors, but we
            // don't have to correctly figure out all those paths
            // ahead of time, since that is flakier

            print("error: no Package.swift found", to: &stderr)
            exit(1)
        }
    }
    return root
}
