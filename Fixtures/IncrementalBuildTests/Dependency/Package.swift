/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageDescription

// For testing whether removing/readding a target incrementally builds correctly
let package = Package(
    name: "Dependency",
    dependencies: [
    .Package(url: "../DependencyLib", majorVersion: 1),
    ]
)
