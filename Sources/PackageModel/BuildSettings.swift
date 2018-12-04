/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

public enum BuildConfiguration: String {
    case debug
    case release

    public var dirname: String {
        switch self {
            case .debug: return "debug"
            case .release: return "release"
        }
    }
}

/// A build setting condition.
public protocol BuildSettingsCondition {}

/// Namespace for build settings.
public enum BuildSettings {

    /// Build settings declarations.
    public struct Declaration: Hashable {
        // Swift.
        public static let SWIFT_ACTIVE_COMPILATION_CONDITIONS: Declaration = .init("SWIFT_ACTIVE_COMPILATION_CONDITIONS")
        public static let OTHER_SWIFT_FLAGS: Declaration = .init("OTHER_SWIFT_FLAGS")

        // C family.
        public static let GCC_PREPROCESSOR_DEFINITIONS: Declaration = .init("GCC_PREPROCESSOR_DEFINITIONS")
        public static let HEADER_SEARCH_PATHS: Declaration = .init("HEADER_SEARCH_PATHS")
        public static let OTHER_CFLAGS: Declaration = .init("OTHER_CFLAGS")
        public static let OTHER_CPLUSPLUSFLAGS: Declaration = .init("OTHER_CPLUSPLUSFLAGS")
    
        // Linker.
        public static let OTHER_LDFLAGS: Declaration = .init("OTHER_LDFLAGS")
        public static let LINK_LIBRARIES: Declaration = .init("LINK_LIBRARIES")
        public static let LINK_FRAMEWORKS: Declaration = .init("LINK_FRAMEWORKS")

        /// The declaration name.
        public let name: String
    
        private init(_ name: String) {
            self.name = name
        }

        /// The list of settings that are considered as unsafe build settings.
        public static let unsafeSettings: Set<Declaration> = [
            OTHER_CFLAGS,  OTHER_CPLUSPLUSFLAGS, OTHER_SWIFT_FLAGS, OTHER_LDFLAGS,
        ]
    }

    /// Platforms condition implies that an assignment is valid on these platforms.
    public struct PlatformsCondition: BuildSettingsCondition {
        public var platforms: [Platform] {
            didSet {
                assert(!platforms.isEmpty, "List of platforms should not be empty")
            }
        }

        public init() {
            self.platforms = []
        }
    }

    /// A configuration condition implies that an assignment is valid on
    /// a particular build configuration.
    public struct ConfigurationCondition: BuildSettingsCondition {
        public var config: BuildConfiguration

        public init(_ config: BuildConfiguration) {
            self.config = config
        }
    }

    /// An individual build setting assignment.
    public struct Assignment {
        /// The assignment value.
        public var value: [String]

        // FIXME: This should be a set but we need Equatable existential (or AnyEquatable) for that.
        /// The condition associated with this assignment.
        public var conditions: [BuildSettingsCondition]

        public init() { 
            self.conditions = []
            self.value = []
        }
    }

    /// Build setting assignment table which maps a build setting to a list of assignments.
    public struct AssignmentTable {
        public private(set) var assignments: [Declaration: [Assignment]]

        public init() {
            assignments = [:]
        }

        /// Add the given assignment to the table.
        mutating public func add(_ assignment: Assignment, for decl: Declaration) {
            // FIXME: We should check for duplicate assignments.
            assignments[decl, default: []].append(assignment)
        }
    }

    /// Provides a view onto assignment table with a given set of bound parameters.
    ///
    /// This class can be used to get the assignments matching the bound parameters.
    public final class Scope {
        /// The assignment table.
        public let table: AssignmentTable

        /// The bound platform.
        public let boundPlatform: Platform

        /// The bound build configuration.
        public let boundConfig: BuildConfiguration

        public init(_ table: AssignmentTable, boundCondition: (Platform, BuildConfiguration)) {
            self.table = table
            self.boundPlatform = boundCondition.0
            self.boundConfig = boundCondition.1
        }

        /// Evaluate the given declaration and return the values matching the bound parameters.
        public func evaluate(_ decl: Declaration) -> [String] {
            // Return nil if there is no entry for this declaration.
            guard let assignments = table.assignments[decl] else {
                return []
            }

            var values: [String] = []

            // Add values from each assignment if it satisfies the bound parameters.
            for assignment in assignments {

                if let configCondition = assignment.conditions.compactMap({ $0 as? ConfigurationCondition }).first {
                    if configCondition.config != boundConfig {
                        continue
                    }
                }

                if let platformsCondition = assignment.conditions.compactMap({ $0 as? PlatformsCondition }).first {
                    if !platformsCondition.platforms.contains(boundPlatform) {
                        continue
                    }
                }

                values += assignment.value
            }

            return values
        }
    }
}
