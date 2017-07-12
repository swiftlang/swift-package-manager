/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Support C language standards.
public enum CLanguageStandard: String {
    case c89
    case c90
    case iso9899_1990 = "iso9899:1990"
    case iso9899_199409 = "iso9899:1994"
    case gnu89
    case gnu90
    case c99
    case iso9899_1999 = "iso9899:1999"
    case gnu99
    case c11
    case iso9899_2011 = "iso9899:2011"
    case gnu11
}

/// Supported C++ language standards.
public enum CXXLanguageStandard: String {
    case cxx98 = "c++98"
    case cxx03 = "c++03"
    case gnucxx98 = "gnu++98"
    case gnucxx03 = "gnu++03"
    case cxx11 = "c++11"
    case gnucxx11 = "gnu++11"
    case cxx14 = "c++14"
    case gnucxx14 = "gnu++14"
    case cxx1z = "c++1z"
    case gnucxx1z = "gnu++1z"
}

extension CLanguageStandard {
    func toJSON() -> JSON {
        return .string(self.rawValue)
    }
}

extension CXXLanguageStandard {
    func toJSON() -> JSON {
        return .string(self.rawValue)
    }
}
