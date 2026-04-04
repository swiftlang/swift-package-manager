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

import Basics

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
            isPackageAccessModifierSupported: Bool = false,
            codesizeProfileEnabled: Bool = false,
            emitSILFiles: Bool = false,
            emitIRFiles: Bool = false,
            emitOptimizationRecord: Bool = false,
            silOutputDirectory: AbsolutePath? = nil,
            irOutputDirectory: AbsolutePath? = nil,
            optimizationRecordDirectory: AbsolutePath? = nil,
            enableCompilationCaching: Bool = false,
            compilationCachePath: AbsolutePath? = nil
        ) {
            self.canRenameEntrypointFunctionName = canRenameEntrypointFunctionName
            self.enableParseableModuleInterfaces = enableParseableModuleInterfaces
            self.explicitTargetDependencyImportCheckingMode = explicitTargetDependencyImportCheckingMode
            self.useIntegratedSwiftDriver = useIntegratedSwiftDriver
            self.isPackageAccessModifierSupported = isPackageAccessModifierSupported
            self.codesizeProfileEnabled = codesizeProfileEnabled
            self.emitSILFiles = emitSILFiles
            self.emitIRFiles = emitIRFiles
            self.emitOptimizationRecord = emitOptimizationRecord
            self.silOutputDirectory = silOutputDirectory
            self.irOutputDirectory = irOutputDirectory
            self.optimizationRecordDirectory = optimizationRecordDirectory
            self.enableCompilationCaching = enableCompilationCaching
            self.compilationCachePath = compilationCachePath
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

        /// Whether the version of Swift Driver used in the currently selected toolchain
        /// supports `-package-name` options.
        @_spi(SwiftPMInternal)
        public var isPackageAccessModifierSupported: Bool

        /// Whether code size profiling mode is enabled
        public var codesizeProfileEnabled: Bool

        /// Whether to emit SIL files
        public var emitSILFiles: Bool

        /// Whether to emit LLVM IR files
        public var emitIRFiles: Bool

        /// Whether to emit optimization records
        public var emitOptimizationRecord: Bool

        /// Output directory for SIL files.
        public var silOutputDirectory: AbsolutePath?

        /// Output directory for IR files.
        public var irOutputDirectory: AbsolutePath?

        /// Output directory for optimization record files.
        public var optimizationRecordDirectory: AbsolutePath?

        /// Whether to enable CAS-based compilation caching.
        public var enableCompilationCaching: Bool

        /// Path to the CAS database directory for compilation caching.
        public var compilationCachePath: AbsolutePath?
    }
}
