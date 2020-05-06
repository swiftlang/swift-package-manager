/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The supported C language standard to use for compiling C sources in the package.
public enum CLanguageStandard: String, Encodable {
    /// The identifier for the C89 language standard.
    case c89
    /// The identifier for the C90 language standard.
    case c90
    /// The identifier for the ISO 9899:1990 language standard.
    case iso9899_1990 = "iso9899:1990"
    /// The identifier for the ISO 9899:1994 language standard.
    case iso9899_199409 = "iso9899:1994"
    /// The identifier for the GNU89 language standard.
    case gnu89
    /// The identifier for the GNU90 language standard.
    case gnu90
    /// The identifier for the C99 language standard.
    case c99
    /// The identifier for the ISO 9899:1999 language standard.
    case iso9899_1999 = "iso9899:1999"
    /// The identifier for the GNU99 language standard.
    case gnu99
    /// The identifier for the C11 language standard.
    case c11
    /// The identifier for the ISO 9899:2011 language standard.
    case iso9899_2011 = "iso9899:2011"
    /// The identifier for the GNU11 language standard.
    case gnu11
}

/// The supported C++ language standards to use for compiling C++ sources in the package.
public enum CXXLanguageStandard: String, Encodable {
    /// The identifier for the C++98 language standard.
    case cxx98 = "c++98"
    /// The identifier for the C++03 language standard.
    case cxx03 = "c++03"
    /// The identifier for the GNU++98 language standard.
    case gnucxx98 = "gnu++98"
    /// The identifier for the GNU++03 language standard.
    case gnucxx03 = "gnu++03"
    /// The identifier for the C++11 language standard.
    case cxx11 = "c++11"
    /// The identifier for the GNU++11 language standard.
    case gnucxx11 = "gnu++11"
    /// The identifier for the C++14 language standard.
    case cxx14 = "c++14"
    /// The identifier for the GNU++14 language standard.
    case gnucxx14 = "gnu++14"
    /// The identifier for the C++1z language standard.
    case cxx1z = "c++1z"
    /// The identifier for the GNU++1z language standard.
    case gnucxx1z = "gnu++1z"
    /// The identifier for the C++17 language standard.
    @available(_PackageDescription, introduced: 999.0)
    case cxx17 = "c++17"
    /// The identifier for the GNU++17 language standard.
    @available(_PackageDescription, introduced: 999.0)
    case gnucxx17 = "gnu++17"
    /// The identifier for the C++2a language standard.
    @available(_PackageDescription, introduced: 999.0)
    case cxx2a = "c++2a"
    /// The identifier for the GNU++2a language standard.
    @available(_PackageDescription, introduced: 999.0)
    case gnucxx2a = "gnu++2a"
}

#if !PACKAGE_DESCRIPTION_4
/// The version of the Swift language to use for compiling Swift sources in the package.
public enum SwiftVersion {
    @available(_PackageDescription, introduced: 4, obsoleted: 5)
    case v3

    @available(_PackageDescription, introduced: 4)
    case v4

    @available(_PackageDescription, introduced: 4)
    case v4_2

    @available(_PackageDescription, introduced: 5)
    case v5

    /// A user-defined value for the Swift version.
    ///
    /// The value is passed as-is to the Swift compiler's `-swift-version` flag.
    case version(String)
}

extension SwiftVersion: Encodable {

    public func encode(to encoder: Encoder) throws {
        let value: String

        switch self {
        case .v3:
            value = "3"
        case .v4:
            value = "4"
        case .v4_2:
            value = "4.2"
        case .v5:
            value = "5"
        case .version(let v):
            value = v
        }

        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
#endif
