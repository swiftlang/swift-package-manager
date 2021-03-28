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

/// The target build context provides information about the target to which
/// the plugin is being applied, as well as contextual information such as
/// the paths of the directories to which commands should be configured to
/// write their outputs. This information should be used when generating the
/// commands to be run during the build.
public let targetBuildContext: TargetBuildContext = CreateTargetBuildContext()

/// The command constructor lets the plugin create commands that will run
/// during the build, including their full command lines. All paths should
/// be based on the ones passed to the plugin in the target build context.
public let commandConstructor = CommandConstructor()

/// The diagnostics emitter lets the plugin emit errors, warnings, and remarks
/// for issues discovered by the plugin. Note that diagnostics from the plugin
/// itself are relatively rare, and relate such things as missing tools or to
/// problems constructing the build command. Diagnostics from the build tools
/// themselves are processed in the same way as any other output from a build
/// tool.
public let diagnosticsEmitter = DiagnosticsEmitter()
