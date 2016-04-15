/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension ModuleDependencyTests {
    static var allTests : [(String, ModuleDependencyTests -> () throws -> Void)] {
        return [
           ("test1", test1),
           ("test2", test2),
           ("test3", test3),
           ("test4", test4),
           ("test5", test5),
           ("test6", test6),
        ]
    }
}

extension PrimitiveResolutionTests {
    static var allTests : [(String, PrimitiveResolutionTests -> () throws -> Void)] {
        return [
           ("testResolvesSingleSwiftModule", testResolvesSingleSwiftModule),
           ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
           ("testResolvesSingleClangModule", testResolvesSingleClangModule),
        ]
    }
}

extension ValidSourcesTests {
    static var allTests : [(String, ValidSourcesTests -> () throws -> Void)] {
        return [
            ("testDotFilesAreIgnored", testDotFilesAreIgnored),
        ]
    }
}
