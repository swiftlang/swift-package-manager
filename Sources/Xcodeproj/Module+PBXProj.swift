/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
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
 a unique suffix where the suffix is the filename or target name
 and since we guarantee uniqueness at the PackageDescription
 layer for these properties we satisfy the above constraints.
*/

import Basic
import PackageModel
import PackageLoading

extension ResolvedTarget {

    var infoPlistFileName: String {
        return "\(c99name)_Info.plist"
    }

    var productType: String {
        switch type {
        case .test:
            return "com.apple.product-type.bundle.unit-test"
        case .library:
            return "com.apple.product-type.framework"
        case .executable:
            return "com.apple.product-type.tool"
        case .systemModule:
            fatalError()
        }
    }

    var explicitFileType: String {
        switch type {
        case .test:
            return "compiled.mach-o.wrapper.cfbundle"
        case .library:
            return "wrapper.framework"
        case .executable:
            return "compiled.mach-o.executable"
        case .systemModule:
            fatalError()
        }
    }

    var productPath: RelativePath {
        switch type {
        case .test:
            return RelativePath("\(c99name).xctest")
        case .library:
            return RelativePath("\(c99name).framework")
        case .executable:
            return RelativePath(name)
        case .systemModule:
            fatalError()
        }
    }

    var productName: String {
        switch type {
        case .library:
            // you can go without a lib prefix, but something unexpected will break
            return "'lib$(TARGET_NAME)'"
        case .test, .executable:
            return "'$(TARGET_NAME)'"
        case .systemModule:
            fatalError()
        }
    }
}
