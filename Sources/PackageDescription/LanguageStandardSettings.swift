/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2017 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The supported C language standard to use for compiling C sources in the package.
///
/// Aliases are available for some C language standards. For example,
/// use `c89`, `c90`, or `iso9899_1990` for the "ISO C 1990" standard.
/// To learn more, read the [Clang Compiler User's Manual][1].
///
/// [1]: <https://clang.llvm.org/docs/UsersManual.html#differences-between-various-standard-modes>
public enum CLanguageStandard: String, Encodable {

    /// ISO C 1990.
    case c89

    /// ISO C 1990.
    case c90

    /// ISO C 1999.
    case c99

    /// ISO C 2011.
    case c11

    /// ISO C 2017.
    @available(_PackageDescription, introduced: 999.0)
    case c17

    /// ISO C 2017.
    @available(_PackageDescription, introduced: 999.0)
    case c18

    /// Working Draft for ISO C2x.
    @available(_PackageDescription, introduced: 999.0)
    case c2x

    /// ISO C 1990 with GNU extensions.
    case gnu89

    /// ISO C 1990 with GNU extensions.
    case gnu90

    /// ISO C 1999 with GNU extensions.
    case gnu99

    /// ISO C 2011 with GNU extensions.
    case gnu11

    /// ISO C 2017 with GNU extensions.
    @available(_PackageDescription, introduced: 999.0)
    case gnu17

    /// ISO C 2017 with GNU extensions.
    @available(_PackageDescription, introduced: 999.0)
    case gnu18

    /// Working Draft for ISO C2x with GNU extensions.
    @available(_PackageDescription, introduced: 999.0)
    case gnu2x

    /// ISO C 1990.
    case iso9899_1990 = "iso9899:1990"

    /// ISO C 1990 with amendment 1.
    case iso9899_199409 = "iso9899:199409"

    /// ISO C 1999.
    case iso9899_1999 = "iso9899:1999"

    /// ISO C 2011.
    case iso9899_2011 = "iso9899:2011"

    /// ISO C 2017.
    @available(_PackageDescription, introduced: 999.0)
    case iso9899_2017 = "iso9899:2017"

    /// ISO C 2017.
    @available(_PackageDescription, introduced: 999.0)
    case iso9899_2018 = "iso9899:2018"
}

/// The supported C++ language standard to use for compiling C++ sources in the package.
///
/// Aliases are available for some C++ language standards. For example,
/// use `cxx98` or `cxx03` for the "ISO C++ 1998 with amendments" standard.
/// To learn more, read the [C++ Support in Clang][1] status page.
///
/// [1]: <https://clang.llvm.org/cxx_status.html>
public enum CXXLanguageStandard: String, Encodable {

    /// ISO C++ 1998 with amendments.
    case cxx98 = "c++98"

    /// ISO C++ 1998 with amendments.
    case cxx03 = "c++03"

    /// ISO C++ 2011 with amendments.
    case cxx11 = "c++11"

    /// ISO C++ 2014 with amendments.
    case cxx14 = "c++14"

    /// ISO C++ 2017 with amendments.
    @available(_PackageDescription, introduced: 999.0)
    case cxx17 = "c++17"

    /// ISO C++ 2017 with amendments.
    @available(_PackageDescription, introduced: 4, deprecated: 999.0, renamed: "cxx17")
    case cxx1z = "c++1z"

    /// ISO C++ 2020 DIS.
    @available(_PackageDescription, introduced: 999.0)
    case cxx20 = "c++20"

    /// ISO C++ 1998 with amendments and GNU extensions.
    case gnucxx98 = "gnu++98"

    /// ISO C++ 1998 with amendments and GNU extensions.
    case gnucxx03 = "gnu++03"

    /// ISO C++ 2011 with amendments and GNU extensions.
    case gnucxx11 = "gnu++11"

    /// ISO C++ 2014 with amendments and GNU extensions.
    case gnucxx14 = "gnu++14"

    /// ISO C++ 2017 with amendments and GNU extensions.
    @available(_PackageDescription, introduced: 999.0)
    case gnucxx17 = "gnu++17"

    /// ISO C++ 2017 with amendments and GNU extensions.
    @available(_PackageDescription, introduced: 4, deprecated: 999.0, renamed: "gnucxx17")
    case gnucxx1z = "gnu++1z"

    /// ISO C++ 2020 DIS with GNU extensions.
    @available(_PackageDescription, introduced: 999.0)
    case gnucxx20 = "gnu++20"
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
