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
    @Tag public static var UserWorkflow: Tag
}

extension Tag.TestSize {
    @Tag public static var small: Tag
    @Tag public static var medium: Tag
    @Tag public static var large: Tag
}

extension Tag.Feature {
    public enum Command {}
    public enum PackageType {}
    public enum ProductType {}
    public enum TargetType {}

    @Tag public static var CodeCoverage: Tag
    @Tag public static var Mirror: Tag
    @Tag public static var NetRc: Tag
    @Tag public static var Resource: Tag
    @Tag public static var SpecialCharacters: Tag
    @Tag public static var Snippets: Tag
    @Tag public static var Traits: Tag

}

extension Tag.Feature.Command {
    public enum Package {}
    public enum PackageRegistry {}
    @Tag public static var Build: Tag
    @Tag public static var Run: Tag
    @Tag public static var Sdk: Tag
    @Tag public static var Test: Tag
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
    @Tag public static var Resolve: Tag
    @Tag public static var ShowDependencies: Tag
    @Tag public static var ShowExecutables: Tag
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
    @Tag public static var Executable: Tag
    @Tag public static var Library: Tag
    @Tag public static var Macro: Tag
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
    @Tag public static var Executable: Tag
    @Tag public static var Tool: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var BuildToolPlugin: Tag
    @Tag public static var CommandPlugin: Tag
    @Tag public static var Macro: Tag
}
