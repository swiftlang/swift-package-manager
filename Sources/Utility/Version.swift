/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// Explicitly re-export Version from Utility.
//
// FIXME: Conceptually, we shouldn't explicitly depend on any of the types in
// PackageDescription, since we want the API to be fully decoupled from the
// exact SwiftPM version. That is important if we ever need to load manifests
// from other versions of the package manager within a single build.

@_exported import struct PackageDescription.Version
