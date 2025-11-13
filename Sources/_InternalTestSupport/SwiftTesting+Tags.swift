/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Testing

extension Tag {
    public enum TestSize {}
    public enum Feature {}
    public enum Platform {}
    @Tag public static var UserWorkflow: Tag
}

extension Tag.TestSize {
    @Tag public static var small: Tag
    @Tag public static var medium: Tag
    @Tag public static var large: Tag
}

extension Tag.Platform {
    @Tag public static var FileSystem: Tag
}

extension Tag.Feature {
    public enum Command {}
    public enum CommandLineArguments {}
    public enum EnvironmentVariables {}
    public enum PackageType {}
    public enum ProductType {}
    public enum TargetType {}
    public enum Product {}

    @Tag public static var BuildCache: Tag
    @Tag public static var CodeCoverage: Tag
    @Tag public static var CTargets: Tag
    @Tag public static var DependencyResolution: Tag
    @Tag public static var LibraryEvolution: Tag
    @Tag public static var ModuleAliasing: Tag
    @Tag public static var Mirror: Tag
    @Tag public static var NetRc: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var Resource: Tag
    @Tag public static var SourceGeneration: Tag
    @Tag public static var SpecialCharacters: Tag
    @Tag public static var Snippets: Tag
    @Tag public static var TestDiscovery: Tag
    @Tag public static var Traits: Tag
    @Tag public static var TargetSettings: Tag
    @Tag public static var TaskBacktraces: Tag
    @Tag public static var Version: Tag
}

extension Tag.Feature.Command {
    public enum Package {}
    public enum PackageRegistry {}
    @Tag public static var Build: Tag
    @Tag public static var Run: Tag
    @Tag public static var Sdk: Tag
    @Tag public static var Test: Tag
}

extension Tag.Feature.CommandLineArguments {
    public enum Experimental {}
    @Tag public static var BuildSystem: Tag
    @Tag public static var BuildTests: Tag
    @Tag public static var Configuration: Tag
    @Tag public static var DisableGetTaskAllowEntitlement: Tag
    @Tag public static var EnableParseableModuleInterfaces: Tag
    @Tag public static var EnableGetTaskAllowEntitlement: Tag
    @Tag public static var EnableTestDiscovery: Tag
    @Tag public static var ExplicitTargetDependencyImportCheck: Tag
    @Tag public static var Help: Tag
    @Tag public static var Product: Tag
    @Tag public static var PrintManifestJobGraph: Tag
    @Tag public static var PrintPIFManifestGraph: Tag
    @Tag public static var Quiet: Tag
    @Tag public static var ShowBinPath: Tag
    @Tag public static var Target: Tag
    @Tag public static var Toolset: Tag
    @Tag public static var Triple: Tag
    @Tag public static var Version: Tag
    @Tag public static var Verbose: Tag
    @Tag public static var VeryVerbose: Tag
    @Tag public static var Xlinker: Tag
    @Tag public static var XbuildToolsSwiftc: Tag
    @Tag public static var Xcc: Tag
    @Tag public static var Xcxx: Tag
    @Tag public static var Xld: Tag
    @Tag public static var Xswiftc: Tag
    @Tag public static var TestParallel: Tag
    @Tag public static var TestNoParallel: Tag
    @Tag public static var TestOutputXunit: Tag
    @Tag public static var TestEnableSwiftTesting: Tag
    @Tag public static var TestDisableSwiftTesting: Tag
    @Tag public static var TestEnableXCTest: Tag
    @Tag public static var TestDisableXCTest: Tag
    @Tag public static var TestFilter: Tag
    @Tag public static var TestSkip: Tag
    @Tag public static var SkipBuild: Tag
    @Tag public static var EnableCodeCoverage: Tag
}

extension Tag.Feature.CommandLineArguments.Experimental {
    @Tag public static var BuildDylibsAsFrameworks: Tag
    @Tag public static var PruneUnusedDependencies: Tag
}
extension Tag.Feature.EnvironmentVariables {
    @Tag public static var CUSTOM_SWIFT_VERSION: Tag
    @Tag public static var SWIFT_EXEC: Tag
    @Tag public static var SWIFT_EXEC_MANIFEST: Tag
    @Tag public static var SWIFT_ORIGINAL_PATH: Tag
}

extension Tag.Feature.Command.Package {
    @Tag public static var General: Tag
    @Tag public static var AddDependency: Tag
    @Tag public static var AddProduct: Tag
    @Tag public static var ArchiveSource: Tag
    @Tag public static var AddSetting: Tag
    @Tag public static var AddTarget: Tag
    @Tag public static var AddTargetDependency: Tag
    @Tag public static var BuildPlugin: Tag
    @Tag public static var Clean: Tag
    @Tag public static var CommandPlugin: Tag
    @Tag public static var CompletionTool: Tag
    @Tag public static var Config: Tag
    @Tag public static var Describe: Tag
    @Tag public static var DumpPackage: Tag
    @Tag public static var DumpSymbolGraph: Tag
    @Tag public static var Edit: Tag
    @Tag public static var Init: Tag
    @Tag public static var Migrate: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var Reset: Tag
    @Tag public static var PurgeCache: Tag
    @Tag public static var Resolve: Tag
    @Tag public static var ShowDependencies: Tag
    @Tag public static var ShowExecutables: Tag
    @Tag public static var ShowTraits: Tag
    @Tag public static var ToolsVersion: Tag
    @Tag public static var Unedit: Tag
    @Tag public static var Update: Tag
}

extension Tag.Feature.Command.PackageRegistry {
    @Tag public static var General: Tag
    @Tag public static var Login: Tag
    @Tag public static var Logout: Tag
    @Tag public static var Publish: Tag
    @Tag public static var Set: Tag
    @Tag public static var Unset: Tag
}

extension Tag.Feature.TargetType {
    public enum BinaryTarget {}
    @Tag public static var Executable: Tag
    @Tag public static var Library: Tag
    @Tag public static var Macro: Tag
    @Tag public static var Test: Tag
}

extension Tag.Feature.TargetType.BinaryTarget {
    @Tag public static var ArtifactBundle: Tag
    @Tag public static var XCFramework: Tag
}

extension Tag.Feature.ProductType {
    @Tag public static var DynamicLibrary: Tag
    @Tag public static var Executable: Tag
    @Tag public static var Library: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var StaticLibrary: Tag
}
extension Tag.Feature.PackageType {
    @Tag public static var Library: Tag
    @Tag public static var Empty: Tag
    @Tag public static var Executable: Tag
    @Tag public static var Tool: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var BuildToolPlugin: Tag
    @Tag public static var CommandPlugin: Tag
    @Tag public static var Macro: Tag
}

extension Tag.Feature.Product {
    @Tag public static var Execute: Tag
    @Tag public static var Link: Tag
}
