//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct DriverParameters: Encodable {

    /// Whether to use the integrated Swift driver rather than shelling out
    /// to a separate process.
    public var useIntegratedSwiftDriver: Bool

    /// Whether to use the explicit module build flow (with the integrated driver).
    public var useExplicitModuleBuild: Bool
}
