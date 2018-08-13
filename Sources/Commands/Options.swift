/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import Build

public class ToolOptions {
    /// Custom arguments to pass to C compiler, swift compiler and the linker.
    public var buildFlags = BuildFlags()
    
    /// Build configuration.
    public var configuration: Build.Configuration = .debug

    /// The custom build directory, if provided.
    public var buildPath: AbsolutePath?

    /// The custom working directory that the tool should operate in (deprecated).
    public var chdir: AbsolutePath?
    
    /// The custom working directory that the tool should operate in.
    public var packagePath: AbsolutePath?

    /// Enable prefetching in resolver which will kick off parallel git cloning.
    public var shouldEnableResolverPrefetching = true

    /// If print version option was passed.
    public var shouldPrintVersion: Bool = false

    /// The verbosity of informational output.
    public var verbosity: Int = 0

    /// Disables sandboxing when executing subprocesses.
    public var shouldDisableSandbox = false

    /// Disables manifest caching.
    public var shouldDisableManifestCaching = false

    /// Path to the compilation destination describing JSON file.
    public var customCompileDestination: AbsolutePath?

    /// If should link the Swift stdlib statically.
    public var shouldLinkStaticSwiftStdlib = false
    
    /// If should enable building with llbuild library.
    public var shouldEnableLLBuildLibrary = true

    /// Skip updating dependencies from their remote during a resolution.
    public var skipDependencyUpdate = false

    /// Which compile-time sanitizers should be enabled.
    public var sanitizers = EnabledSanitizers()

    public required init() {}
}
