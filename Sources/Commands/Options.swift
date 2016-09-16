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
    public var enableNewResolver = false
    public var colorMode: ColorWrap.Mode = .Auto
    public var verbosity: Int = 0
    public var buildPath: AbsolutePath?

    public init()
    {}
}

public struct Flag {
    public static let chdir = "--chdir"
    public static let C = "-C"
}
