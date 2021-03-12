/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/*
 Like package manifests, package plugins are Swift scripts that use API
 from a specialized PackagePlugin library provided by SwiftPM. Plugins
 run in a sandbox and have read-only access to the package directory.

 The input to a package plugin is passed by SwiftPM when it is invoked,
 and can be accessed through the `targetBuildContext` global. The plugin
 generates commands to run during the build using the `commandConstructor`
 global, and can emit diagnostics using the `diagnosticsEmitter` global.
 */

/// Provides information about the target being built, as well as contextual
/// information such as the paths of the directories to which commands should
/// be configured to write their outputs. This information should be used as
/// part of generating the commands to be run during the build.
public let targetBuildContext: TargetBuildContext = CreateTargetBuildContext()

/// Constructs commands to run during the build, including full command lines.
/// All paths should be based on the ones passed to the plugin in the target
/// build context.
public let commandConstructor = CommandConstructor()

/// Emits errors, warnings, and remarks to be shown as a result of running the
/// plugin. After emitting one or more errors, the plugin should return a
/// non-zero exit code.
public let diagnosticsEmitter = DiagnosticsEmitter()
