/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import POSIX
import PackageModel
import Utility

public class Options {
    public var chdir: AbsolutePath?
    public var path = Path()

    public class Path {
        public lazy var root = getroot()
        public var packages: AbsolutePath { return root.appending("Packages") }

        public var build: AbsolutePath {
            get { return _build != nil ? AbsolutePath(_build!) : getroot().appending(".build") }
            set { _build = newValue.asString }
        }

        private var _build = getenv("SWIFT_BUILD_PATH")?.abspath
    }

    public init()
    {}
}

public struct Flag {
    public static let chdir = "--chdir"
    public static let C = "-C"
}

private func getroot() -> AbsolutePath {
    var root = AbsolutePath(getcwd())
    while try! !isFile(root.appending(component: Manifest.filename)) {
        root = root.parentDirectory

        guard root != "/" else {
            // abort because lazy properties cannot throw and we
            // want erroring on no manifest found to be “lazy” so
            // any path that requires this property errors, but we
            // don't have to correctly figure out all those paths
            // ahead of time, since that is flakier
            
            let header = ColorWrap.wrap("error:", with: .Red, for: .stdErr) 

            print("\(header): no Package.swift found", to: &stderr)
            exit(1)
        }
    }
    return root
}
