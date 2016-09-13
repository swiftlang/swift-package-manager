/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------

 In an effort to provide:

  1. Unique reference identifiers
  2. Human readable reference identifiers
  3. Stable reference identifiers

 (as opposed to the generated UUIDs Xcode typically generates)

 We create identifiers with a constant-length unique prefix and
 a unique suffix where the suffix is the filename or module name
 and since we guarantee uniqueness at the PackageDescription
 layer for these properties we satisfy the above constraints.
*/

import Basic
import PackageModel
import PackageLoading

extension Module  {
    
    var isLibrary: Bool {
        return type == .library
    }

    var infoPlistFileName: String {
        return "\(c99name)_Info.plist"
    }

    var productType: String {
        if isTest {
            return "com.apple.product-type.bundle.unit-test"
        } else if isLibrary {
            return "com.apple.product-type.framework"
        } else {
            return "com.apple.product-type.tool"
        }
    }

    var explicitFileType: String {
        if isTest {
            return "compiled.mach-o.wrapper.cfbundle"
        } else if isLibrary {
            return "wrapper.framework"
        } else {
            return "compiled.mach-o.executable"
        }
    }

    var productPath: RelativePath {
        if isTest {
            return RelativePath("\(c99name).xctest")
        } else if isLibrary {
            return RelativePath("\(c99name).framework")
        } else {
            return RelativePath(name)
        }
    }

    var productName: String {
        if isLibrary && !isTest {
            // you can go without a lib prefix, but something unexpected will break
            return "'lib$(TARGET_NAME)'"
        } else {
            return "'$(TARGET_NAME)'"
        }
    }
}
