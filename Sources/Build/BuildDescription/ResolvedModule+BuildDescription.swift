//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct TSCBasic.StringError
import struct PackageGraph.ResolvedModule
import enum PackageModel.BuildSettings

import SPMBuildCore

extension ResolvedModule {
    func tempsPath(_ buildParameters: BuildParameters) -> AbsolutePath {
        let suffix = buildParameters.suffix
        return BuildOperation.buildProductsPath(for: buildParameters).appending(component: "\(self.c99name)\(suffix).build")
    }
}

private struct NativeBuildSystemUnsupportedSetting {
    let declarations: [BuildSettings.Declaration]
    let description: String

    static let all: [NativeBuildSystemUnsupportedSetting] = [
        .init(
            declarations: [.SWIFT_OBJC_BRIDGING_HEADER],
            description: "bridging headers are"
        ),
        .init(
            declarations: [.SWIFT_OPTIMIZATION_LEVEL, .C_OPTIMIZATION_LEVEL, .CXX_OPTIMIZATION_LEVEL],
            description: "the 'optimizationLevel' build setting is"
        ),
    ]
}

extension ResolvedModule {
    func diagnoseUnsupportedSettings(_ buildParameters: BuildParameters) throws {
        let scope = buildParameters.createScope(for: self)
        for setting in NativeBuildSystemUnsupportedSetting.all {
            if setting.declarations.contains(where: { !scope.evaluate($0).isEmpty }) {
                throw StringError("\(self.name): \(setting.description) not supported when using the native build system.")
            }
        }
    }
}
