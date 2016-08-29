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

// FIXME: The functionality to find the package root path etc should move to `SwiftTool`, and `Options` should be a struct that gets initialized in a clean way other than just on demand.  Right now, for example, if you happen to ask for `path.root` (which doesn't mean the path of the root directory but rather the top-level package directory path) before you change directory to the path specified by `chdir`, you get the wrong value.  This doesn't need to be so complicated, and in particular, behavior shouldn't depend on the order in which properties are asked for.
public class Options {
    public var chdir: AbsolutePath?
    public var path = Path()
    public var enableNewResolver = false

    public class Path {
        public lazy var root = getroot()
        public var packages: AbsolutePath { return root.appending(component: "Packages") }

        public var build: AbsolutePath {
            get { return _build != nil ? AbsolutePath(_build!) : getroot().appending(component: ".build") }
            set { _build = newValue.asString }
        }
        private var _build = getEnvBuildPath()?.asString
    }

    public init()
    {}
}

fileprivate func getEnvBuildPath() -> AbsolutePath? {
    guard let env = getenv("SWIFT_BUILD_PATH") else { return nil }
    return AbsolutePath(env, relativeTo: currentWorkingDirectory)
}

public struct Flag {
    public static let chdir = "--chdir"
    public static let C = "-C"
}

private func getroot() -> AbsolutePath {
    var root = currentWorkingDirectory
    while !isFile(root.appending(component: Manifest.filename)) {
        root = root.parentDirectory

        guard !root.isRoot else {
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
