//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Whether one PIF generation can feed multiple `ConfiguredTarget`s with different platforms.
///
/// `.single` callers (`swift build`, `swift package dump-pif`, library users) materialize
/// exactly one configured target — the triple is fixed, no fan-out is possible. `.multiple`
/// callers (BSP / SourceKit-LSP, Xcode-driven workspace ingestion) can drive a graph
/// resolved once into multiple configured targets at different platforms; the canonical
/// case is an iOS app embedding a watchOS extension that links a SwiftPM package.
///
/// `PIFBuilder` uses this to gate the per-platform plugin invocation fan-out: under
/// `.single`, a plugin usage with `condition: .when(targetPlatforms: [...])` produces at
/// most one invocation pinned to the build platform (and is dropped if that platform
/// isn't in the list); under `.multiple`, the same usage fans out to one invocation per
/// listed platform. Plugin usages without an explicit `targetPlatforms` axis stay
/// untagged in either mode.
public enum PIFConfiguredTargetMode: Sendable, Hashable {
    case single
    case multiple
}
