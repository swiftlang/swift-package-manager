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

import enum Dispatch.DispatchTimeInterval

/// This typealias hides `DispatchTimeInterval` as an implementation detail until we can use `Swift.Duration`, as the
/// latter requires macOS 13.
public typealias SendableTimeInterval = DispatchTimeInterval
