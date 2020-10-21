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

    /// The name of the build setting.
    public enum SettingName: String, Codable, Equatable {
        case headerSearchPath
        case define
        case linkedLibrary
        case linkedFramework

        case unsafeFlags
    }

    /// An individual build setting.
    public struct Setting: Codable, Equatable {

        /// The tool associated with this setting.
        public let tool: Tool

        /// The name of the setting.
        public let name: SettingName

        /// The condition at which the setting should be applied.
        public let condition: PackageConditionDescription?

        /// The value of the setting.
        ///
        /// This is kind of like an "untyped" value since the length
        /// of the array will depend on the setting type.
        public let value: [String]

        public init(
            tool: Tool,
            name: SettingName,
            value: [String],
            condition: PackageConditionDescription? = nil
        ) {
            switch name {
            case .headerSearchPath: fallthrough
            case .define: fallthrough
            case .linkedLibrary: fallthrough
            case .linkedFramework:
                assert(value.count == 1, "\(tool) \(name) \(value)")
                break
            case .unsafeFlags:
                assert(value.count >= 1, "\(tool) \(name) \(value)")
                break
            }

            self.tool = tool
            self.name = name
            self.value = value
            self.condition = condition
        }
    }
}
