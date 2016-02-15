/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

func test(path: String..., args: String? = nil) -> Bool {
    let path = Path.join(path)
    let result: Void?
#if os(OSX)
    var args = ["xcrun", "xctest"]
    args += Process.arguments.dropFirst()
    args += [Path.join(path, "Package.xctest")]
    result = try? system(args)
#else
    result = try? system(Path.join(path, "test-Package"))
#endif
    return result != nil
}
