//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import PackageDescription

let package = Package(
    name: "TargetDeps",
    targets: [
        Target(
            name: "sys",
            dependencies: [.Target(name: "libc")]),
        Target(
            name: "dep",
            dependencies: [.Target(name: "sys"), .Target(name: "libc")])])
