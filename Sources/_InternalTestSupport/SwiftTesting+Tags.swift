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

    @Tag public static var CodeCoverage: Tag
    @Tag public static var Resource: Tag
    @Tag public static var SpecialCharacters: Tag
    @Tag public static var Traits: Tag
}

extension Tag.Feature.Command {
    public enum Package {}
    @Tag public static var Build: Tag
    @Tag public static var Test: Tag
    @Tag public static var Run: Tag
}

extension Tag.Feature.Command.Package {
    @Tag public static var Init: Tag
    @Tag public static var DumpPackage: Tag
    @Tag public static var DumpSymbolGraph: Tag
    @Tag public static var Plugin: Tag
    @Tag public static var Reset: Tag
    @Tag public static var ToolsVersion: Tag
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
