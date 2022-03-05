/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A namespace for target-specific build settings.
public enum TargetBuildSettingDescription {

    /// The tool for which a build setting is declared.
    public enum Tool: String, Codable, Equatable, CaseIterable {
        case c
        case cxx
        case swift
        case linker
    }

    /// The kind of the build setting, with associate configuration
    public enum Kind: Codable, Equatable {
        case headerSearchPath(String)
        case define(String)
        case linkedLibrary(String)
        case linkedFramework(String)

        case unsafeFlags([String])
    }

    /// An individual build setting.
    public struct Setting: Codable, Equatable {

        /// The tool associated with this setting.
        public let tool: Tool

        /// The kind of the setting.
        public let kind: Kind

        /// The condition at which the setting should be applied.
        public let condition: PackageConditionDescription?

        public init(
            tool: Tool,
            kind: Kind,
            condition: PackageConditionDescription? = .none
        ) {
            self.tool = tool
            self.kind = kind
            self.condition = condition
        }
    }
}
