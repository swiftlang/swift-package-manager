/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 [A semantic version](http://semver.org).
*/

public struct Version {
    public enum Component: String {
        case Major, Minor, Patch
    }

    public let (major, minor, patch): (Int, Int, Int)
    public let prereleaseIdentifiers: [String]
    public let buildMetadataIdentifier: String?
    
    public init(_ major: Int, _ minor: Int, _ patch: Int, prereleaseIdentifiers: [String] = [], buildMetadataIdentifier: String? = nil) {
        self.major = Swift.max(major, 0)
        self.minor = Swift.max(minor, 0)
        self.patch = Swift.max(patch, 0)
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifier = buildMetadataIdentifier
    }

    public init?(_ characters: String.CharacterView) {
        let prereleaseStartIndex = characters.indexOf("-")
        let metadataStartIndex = characters.indexOf("+")
        
        let requiredEndIndex = prereleaseStartIndex ?? metadataStartIndex ?? characters.endIndex
        let requiredCharacters = characters.prefixUpTo(requiredEndIndex)
        let requiredComponents = requiredCharacters.split(".", maxSplit: 2, allowEmptySlices: true).map{ String($0) }.flatMap{ Int($0) }.filter{ $0 >= 0 }
        
        guard requiredComponents.count == 3 else {
            return nil
        }

        self.major = requiredComponents[0]
        self.minor = requiredComponents[1]
        self.patch = requiredComponents[2]

        if let prereleaseStartIndex = prereleaseStartIndex {
            let prereleaseEndIndex = metadataStartIndex ?? characters.endIndex
            let prereleaseCharacters = characters[prereleaseStartIndex.successor()..<prereleaseEndIndex]
            prereleaseIdentifiers = prereleaseCharacters.split(".").map{ String($0) }
        } else {
            prereleaseIdentifiers = []
        }
        
        self.buildMetadataIdentifier = metadataStartIndex
                                       .map { characters.suffixFrom($0.successor()) }
                                       .flatMap { $0.isEmpty ? nil : $0 }
                                       .map { String($0) }


    }

    public init?(_ versionString: String) {
        self.init(versionString.characters)
    }

    public func value(forComponent component: Component) -> Int {
        switch component {
            case .Major: return major
            case .Minor: return minor
            case .Patch: return patch
        }
    }
}

// MARK: Equatable

extension Version: Equatable {}

public func ==(v1: Version, v2: Version) -> Bool {
    guard v1.major == v2.major && v1.minor == v2.minor && v1.patch == v2.patch else {
        return false
    }
    
    if v1.prereleaseIdentifiers != v2.prereleaseIdentifiers {
        return false
    }
    
    return v1.buildMetadataIdentifier == v2.buildMetadataIdentifier
}

// MARK: Comparable

extension Version: Comparable {}

public func <(lhs: Version, rhs: Version) -> Bool {
    let lhsComparators = [lhs.major, lhs.minor, lhs.patch]
    let rhsComparators = [rhs.major, rhs.minor, rhs.patch]
    
    if lhsComparators != rhsComparators {
        return lhsComparators.lexicographicalCompare(rhsComparators)
    }
    
    guard lhs.prereleaseIdentifiers.count > 0 else {
        return false // Non-prerelease lhs >= potentially prerelease rhs
    }
    
    guard rhs.prereleaseIdentifiers.count > 0 else {
        return true // Prerelease lhs < non-prerelease rhs 
    }
    
    for (lhsPrereleaseIdentifier, rhsPrereleaseIdentifier) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
        if lhsPrereleaseIdentifier == rhsPrereleaseIdentifier {
            continue
        }
        
        let typedLhsIdentifier: Any = Int(lhsPrereleaseIdentifier) ?? lhsPrereleaseIdentifier
        let typedRhsIdentifier: Any = Int(rhsPrereleaseIdentifier) ?? rhsPrereleaseIdentifier
        
        switch (typedLhsIdentifier, typedRhsIdentifier) {
            case let (int1 as Int, int2 as Int): return int1 < int2
            case let (string1 as String, string2 as String): return string1 < string2
            case (is Int, is String): return true // Int prereleases < String prereleases
            case (is String, is Int): return false
        default:
            return false
        }
    }
    
    return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
}

// MARK: ForwardIndexType

extension Version: BidirectionalIndexType {
    public func successor() -> Version {
        return successor(.Patch)
    }

    public func successor(component: Version.Component) -> Version {
        switch component {
        case .Major:
            return Version(major.successor(), 0, 0)
        case .Minor:
            return Version(major, minor.successor(), 0)
        case .Patch:
            return Version(major, minor, patch.successor())
        }
    }

    public func predecessor() -> Version {
        if patch == 0 {
            if minor == 0 {
                return Version(major - 1, Int.max, Int.max)
            } else {
                return Version(major, minor - 1, Int.max)
            }
        } else {
            return Version(major, minor, patch - 1)
        }
    }
}

// MARK: CustomStringConvertible

extension Version: CustomStringConvertible {
    public var description: String {
        var base = "\(major).\(minor).\(patch)"
        if prereleaseIdentifiers.count > 0 {
            base += "-" + prereleaseIdentifiers.joinWithSeparator(".")
        }
        if let buildMetadataIdentifier = buildMetadataIdentifier {
            base += "+" + buildMetadataIdentifier
        }
        return base
    }
}

// MARK: StringLiteralConvertible

extension Version: StringLiteralConvertible {
    public init(stringLiteral value: String) {
        self.init(value.characters)!
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

// MARK: -

extension Version {
    public static var max: Version {
        return Version(Int.max, Int.max, Int.max)
    }

    public static var min: Version {
        return Version(0, 0, 0)
    }

    public static var maxRange: Range<Version> {
        return self.min..<self.max
    }
}

// MARK: - Specifier

public struct Specifier {
    public let major: Int?
    public let minor: Int?
    public let patch: Int?

    public static var Any: Specifier {
        return Specifier(nil, nil, nil)
    }

    private init(_ major: Int?, _ minor: Int?, _ patch: Int?) {

        self.major = major.map{ Swift.max($0, 0) }
        self.minor = minor.map{ Swift.max($0, 0) }
        self.patch = patch.map{ Swift.max($0, 0) }
    }

    public init?(_ characters: String.CharacterView) {
        let components = characters.split(".", maxSplit: 2).map(String.init).flatMap{ Int($0) }.filter{ $0 >= 0 }

        self.major = components.count >= 1 ? components[0] : nil
        self.minor = components.count >= 2 ? components[1] : nil
        self.patch = components.count >= 3 ? components[2] : nil
    }

    public init(_ major: Int) {
        self.init(major, nil, nil)
    }

    public init(_ major: Int, _ minor: Int) {
        self.init(major, minor, nil)
    }

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.init(major, minor, patch)

    }

    public func value(forComponent component: Version.Component) -> Int? {
        switch component {
        case .Major: return major
        case .Minor: return minor
        case .Patch: return patch
        }
    }
}

// MARK: StringLiteralConvertible

extension Specifier: StringLiteralConvertible {
    public init(stringLiteral value: String) {
        self.init(value.characters)!
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

// MARK: IntegerLiteralConvertible

extension Specifier: IntegerLiteralConvertible {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

// MARK: FloatLiteralConvertible

extension Specifier: FloatLiteralConvertible {
    public init(floatLiteral value: Float) {
        self.init(stringLiteral: "\(value)")
    }
}

// MARK: -

extension Version {
    private init(minimumForSpecifier specifier: Specifier) {
        self.init(specifier.major ?? 0, specifier.minor ?? 0, specifier.patch ?? 0)
    }
}

//

public typealias Requirement = (Version) -> Bool


prefix operator == {}
prefix operator != {}
prefix operator > {}
prefix operator >= {}
prefix operator ~> {}
prefix operator <= {}
//prefix operator < {}


prefix func ==(specifier: Specifier) -> Requirement {
    return { $0 == specifier }
}

prefix func !=(specifier: Specifier) -> Requirement {
    return { $0 != specifier }
}

prefix func >(specifier: Specifier) -> Requirement {
    return { $0 > specifier }
}

prefix func >=(specifier: Specifier) -> Requirement {
    return { $0 >= specifier }
}

prefix func ~>(specifier: Specifier) -> Requirement {
    return { $0 ~> specifier }
}

prefix func <=(specifier: Specifier) -> Requirement {
    return { $0 <= specifier }
}

//prefix func <(specifier: Specifier) -> Requirement {
//    return { $0 < specifier }
//}

// MARK:

func ==(version: Version, specifier: Specifier) -> Bool {
    return version == Version(minimumForSpecifier: specifier)
}

func !=(version: Version, specifier: Specifier) -> Bool {
    return !(version == specifier)
}

func >(version: Version, specifier: Specifier) -> Bool {
    return version >= specifier && version != specifier
}

func >=(version: Version, specifier: Specifier) -> Bool {
    return !(version < specifier)
}

infix operator ~> { associativity left precedence 130 }
func ~>(version: Version, specifier: Specifier) -> Bool {
    guard version >= specifier else { return false }

    switch (specifier.major, specifier.minor, specifier.patch) {
    case (let major?, _, nil):
        return version.major < major.successor()
    case (_, let minor?, _):
        return version.minor < minor.successor()
    default:
        return true
    }
}

func <=(version: Version, specifier: Specifier) -> Bool {
    return version < specifier || version == specifier
}

func <(version: Version, specifier: Specifier) -> Bool {
    return version < Version(minimumForSpecifier: specifier)
}

// MARK: Match Operators

func ~=(lhs: Version, rhs: Requirement) -> Bool {
    return rhs(lhs)
}

func ~=(lhs: Version, rhs: [Requirement]) -> Bool {
    for requirement in rhs {
        guard lhs ~= requirement else { return false }
    }

    return true
}

// MARK: Interval Operators

public func ...(lhs: Specifier, rhs: Specifier) -> Requirement {
    return { (Version(minimumForSpecifier: lhs)...Version(minimumForSpecifier: rhs)).contains($0) }
}

public func ..<(lhs: Specifier, rhs: Specifier) -> Requirement {
    return { (Version(minimumForSpecifier: lhs)..<Version(minimumForSpecifier: rhs)).contains ($0) }
}
