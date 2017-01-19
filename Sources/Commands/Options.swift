/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

public class ToolOptions {
    /// Custom arguments to pass to C compiler, swift compiler and the linker.
    public var buildFlags = BuildFlags()

    /// The custom build directory, if provided.
    public var buildPath: AbsolutePath?

    /// The custom working directory that the tool should operate in.
    public var chdir: AbsolutePath?

    /// The color mode.
    public var colorMode: ColorWrap.Mode = .Auto

    /// If the new resolver should be enabled.
    public var enableNewResolver: Bool = true

    /// Enable prefetching in resolver which will kick off parallel git cloning.
    public var enableResolverPrefetching = false

    /// If print version option was passed.
    public var printVersion: Bool = false

    /// The verbosity of informational output.
    public var verbosity: Int = 0

    public required init() {}

    func absolutePathRelativeToWorkingDir(_ path: String?) -> AbsolutePath? {
        guard let path = path else { return nil }
        return AbsolutePath(path, relativeTo: currentWorkingDirectory)
    }
}

/// Parser conformance for ColorWrap.
extension ColorWrap.Mode: StringEnumArgument {}
