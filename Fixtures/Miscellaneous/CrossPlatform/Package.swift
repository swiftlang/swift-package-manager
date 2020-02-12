// swift-tools-version:5.1

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription

let package = Package(
  name: "CrossPlatform",
  targets: [
    .target(name: "Library"),
    .target(name: "Tool", dependencies: ["Library"]),
    .testTarget(name: "Tests", dependencies: ["Library"])
  ]
)
