//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension BuildParameters {
    /// A mode for explicit import checking
    public enum TargetDependencyImportCheckingMode : Codable {
        case none
        case warn
        case error
    }

    /// Build parameters related to Swift Driver grouped in a single type to aggregate those in one place.
    public struct Driver: Encodable {
        public init(
            canRenameEntrypointFunctionName: Bool = false,
            enableParseableModuleInterfaces: Bool = false,
            explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode = .none,
            useIntegratedSwiftDriver: Bool = false,
            useExplicitModuleBuild: Bool = false,
            isPackageAccessModifierSupported: Bool = false
        ) {
            self.canRenameEntrypointFunctionName = canRenameEntrypointFunctionName
            self.enableParseableModuleInterfaces = enableParseableModuleInterfaces
            self.explicitTargetDependencyImportCheckingMode = explicitTargetDependencyImportCheckingMode
            self.useIntegratedSwiftDriver = useIntegratedSwiftDriver
            self.useExplicitModuleBuild = useExplicitModuleBuild
            self.isPackageAccessModifierSupported = isPackageAccessModifierSupported
        }

        /// Whether to enable the entry-point-function-name feature.
        public var canRenameEntrypointFunctionName: Bool

        /// A flag that indicates this build should check whether targets only import.
        /// their explicitly-declared dependencies
        public var explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode

        /// Whether to enable generation of `.swiftinterface` files alongside.
        /// `.swiftmodule`s.
        public var enableParseableModuleInterfaces: Bool

        /// Whether to use the integrated Swift Driver rather than shelling out
        /// to a separate process.
        public var useIntegratedSwiftDriver: Bool

        /// Whether to use the explicit module build flow (with the integrated driver).
        public var useExplicitModuleBuild: Bool

        /// Whether the version of Swift Driver used in the currently selected toolchain
        /// supports `-package-name` options.
        @_spi(SwiftPMInternal)
        public var isPackageAccessModifierSupported: Bool
    }
}
