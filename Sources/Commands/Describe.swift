/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel
import Foundation


enum DescribeMode: String {
    /// JSON format (guaranteed to be parsable and stable across time).
    case json
    /// Human readable format (not guaranteed to be parsable).
    case text
}


/// Emits a textual description of `package` to `stream`, in the format indicated by `mode`.
func describe(_ package: Package, in mode: DescribeMode, on stream: OutputByteStream) {
    let desc = DescribedPackage(from: package)
    let data: Data
    switch mode {
    case .json:
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // FIXME: This should be extracted into somewhere reusable.
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        }
        else if #available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        }
        else {
            encoder.outputFormatting = [.prettyPrinted]
        }
        data = try! encoder.encode(desc)
    case .text:
        var encoder = PlainTextEncoder()
        encoder.formattingOptions = [.prettyPrinted]
        data = try! encoder.encode(desc)
    }
    stream <<< String(decoding: data, as: UTF8.self) <<< "\n"
    stream.flush()
}


/// Represents a package for the sole purpose of generating a description.
fileprivate struct DescribedPackage: Encodable {
    let name: String
    let path: String
    let toolsVersion: String
    let dependencies: [DescribedPackageDependency]
    let defaultLocalization: String?
    let platforms: [DescribedPlatformRestriction]
    let products: [DescribedProduct]
    let targets: [DescribedTarget]
    let cLanguageStandard: String?
    let cxxLanguageStandard: String?
    let swiftLanguagesVersions: [String]?

    init(from package: Package) {
        self.name = package.name
        self.path = package.path.pathString
        self.toolsVersion = "\(package.manifest.toolsVersion.major).\(package.manifest.toolsVersion.minor)"
            + (package.manifest.toolsVersion.patch == 0 ? "" : ".\(package.manifest.toolsVersion.patch)")
        self.dependencies = package.manifest.dependencies.map { DescribedPackageDependency(from: $0) }
        self.defaultLocalization = package.manifest.defaultLocalization
        self.platforms = package.manifest.platforms.map { DescribedPlatformRestriction(from: $0) }
        self.products = package.products.map {
            DescribedProduct(from: $0, in: package)
        }
        // Create a mapping from the targets to the products to which they contribute directly.  This excludes any
        // contributions that occur through `.product()` dependencies, but since those targets are still part of a
        // product of the package, the set of targets that contribute to products still accurately represents the
        // set of targets reachable from external clients.
        let targetProductPairs = package.products.flatMap{ p in transitiveClosure(p.targets, successors: {
            $0.dependencies.compactMap{ $0.target } }).map{ t in (t, p) }
        }
        let targetsToProducts = Dictionary(targetProductPairs.map{ ($0.0, [$0.1]) }, uniquingKeysWith: { $0 + $1 })
        self.targets = package.targets.map {
            return DescribedTarget(from: $0, in: package, productMemberships: targetsToProducts[$0]?.map{ $0.name })
        }
        self.cLanguageStandard = package.manifest.cLanguageStandard
        self.cxxLanguageStandard = package.manifest.cxxLanguageStandard
        self.swiftLanguagesVersions = package.manifest.swiftLanguageVersions?.map{ $0.description }
    }
    
    /// Represents a platform restriction for the sole purpose of generating a description.
    struct DescribedPlatformRestriction: Encodable {
        let name: String
        let version: String
        let options: [String]?
        
        init(from platform: PlatformDescription) {
            self.name = platform.platformName
            self.version = platform.version
            self.options = platform.options.isEmpty ? nil : platform.options
        }
    }
    
    /// Represents a package dependency for the sole purpose of generating a description.
    struct DescribedPackageDependency: Encodable {
        let name: String?
        let url: String?
        let requirement: PackageDependencyDescription.Requirement?

        init(from dependency: PackageDependencyDescription) {
            self.name = dependency.explicitName
            self.url = dependency.url
            self.requirement = dependency.requirement
        }
    }

    /// Represents a product for the sole purpose of generating a description.
    struct DescribedProduct: Encodable {
        let name: String
        let type: ProductType
        let targets: [String]

        init(from product: Product, in package: Package) {
            self.name = product.name
            self.type = product.type
            self.targets = product.targets.map { $0.name }
        }
    }

    /// Represents a target for the sole purpose of generating a description.
    struct DescribedTarget: Encodable {
        let name: String
        let type: String
        let c99name: String?
        let moduleType: String?
        let path: String
        let sources: [String]
        let resources: [PackageModel.Resource]?
        let targetDependencies: [String]?
        let productMemberships: [String]?
        
        init(from target: Target, in package: Package, productMemberships: [String]?) {
            self.name = target.name
            self.type = target.type.rawValue
            self.c99name = target.c99name
            self.moduleType = String(describing: Swift.type(of: target))
            self.path = target.sources.root.relative(to: package.path).pathString
            self.sources = target.sources.relativePaths.map{ $0.pathString }
            self.resources = target.resources.isEmpty ? nil : target.resources
            self.targetDependencies = target.dependencies.isEmpty ? nil : target.dependencies.compactMap{ $0.target?.name }
            self.productMemberships = productMemberships
        }
    }
}


public struct PlainTextEncoder {
    
    /// The formatting of the output plain-text data.
    public struct FormattingOptions: OptionSet {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// Produce plain-text format with indented output.
        public static let prettyPrinted = FormattingOptions(rawValue: 1 << 0)
    }

    /// The output format to produce. Defaults to `[]`.
    var formattingOptions: FormattingOptions = []

    /// Contextual user-provided information for use during encoding.
    var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Encodes the given top-level value and returns its plain text representation.
    ///
    /// - parameter value: The value to encode.
    /// - returns: A new `Data` value containing the encoded plan-text data.
    /// - throws: An error if any value throws an error during encoding.
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let outputStream = BufferedOutputByteStream()
        let encoder = _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo)
        try value.encode(to: encoder)
        return Data(outputStream.bytes.contents)
    }
    
    /// Private helper function to format key names with an uppercase initial letter and space-separated components.
    private static func displayName(for key: CodingKey) -> String {
        var result = ""
        for ch in key.stringValue {
            if result.isEmpty {
                result.append(ch.uppercased())
            }
            else if ch.isUppercase {
                result.append(" ")
                result.append(ch.lowercased())
            }
            else {
                result.append(ch)
            }
        }
        return result
    }
    
    /// Private Encoder implementation for PlainTextEncoder.
    private struct _PlainTextEncoder: Encoder {
        /// Output stream.
        var outputStream: OutputByteStream

        /// Formatting options set on the top-level encoder.
        let formattingOptions: PlainTextEncoder.FormattingOptions

        /// Contextual user-provided information for use during encoding.
        let userInfo: [CodingUserInfoKey: Any]

        /// The path to the current point in encoding.
        let codingPath: [CodingKey]

        /// Initializes `self` with the given top-level encoder options.
        init(outputStream: OutputByteStream, formattingOptions: PlainTextEncoder.FormattingOptions, userInfo: [CodingUserInfoKey: Any], codingPath: [CodingKey] = []) {
            self.outputStream = outputStream
            self.formattingOptions = formattingOptions
            self.userInfo = userInfo
            self.codingPath = codingPath
        }

        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            return KeyedEncodingContainer(PlainTextKeyedEncodingContainer<Key>(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath))
        }
        
        func unkeyedContainer() -> UnkeyedEncodingContainer {
            return PlainTextUnkeyedEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
       }
        
        func singleValueContainer() -> SingleValueEncodingContainer {
            return TextSingleValueEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
        }

        /// Private KeyedEncodingContainer implementation for PlainTextEncoder.
        private struct PlainTextKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
            let outputStream: OutputByteStream
            let formattingOptions: PlainTextEncoder.FormattingOptions
            let userInfo: [CodingUserInfoKey: Any]
            let codingPath: [CodingKey]
            
            private mutating func emit(_ key: CodingKey, _ value: String?) {
                outputStream <<< String(repeating: "    ", count: codingPath.count)
                outputStream <<< displayName(for: key) <<< ":"
                if let value = value { outputStream <<< " " <<< value }
                outputStream <<< "\n"
            }
            mutating func encodeNil(forKey key: Key) throws { emit(key, "nil") }
            mutating func encode(_ value: Bool, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: String, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Double, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Float, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int8, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int16, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int32, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int64, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt8, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt16, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt32, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt64, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
                emit(key, nil)
                let textEncoder = _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key])
                try value.encode(to: textEncoder)
            }
            
            mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
                emit(key, nil)
                return KeyedEncodingContainer(PlainTextKeyedEncodingContainer<NestedKey>(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key]))
            }
            
            mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
                emit(key, nil)
                return PlainTextUnkeyedEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key])
            }
            
            mutating func superEncoder() -> Encoder {
                return superEncoder(forKey: Key(stringValue: "super")!)
            }
            
            mutating func superEncoder(forKey key: Key) -> Encoder {
                return _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key])
            }
        }
        
        /// Private UnkeyedEncodingContainer implementation for PlainTextEncoder.
        private struct PlainTextUnkeyedEncodingContainer: UnkeyedEncodingContainer {
            let outputStream: OutputByteStream
            let formattingOptions: PlainTextEncoder.FormattingOptions
            let userInfo: [CodingUserInfoKey: Any]
            let codingPath: [CodingKey]
            private(set) var count: Int = 0
            
            private mutating func emit(_ value: String) {
                outputStream <<< String(repeating: "    ", count: codingPath.count)
                outputStream <<< value
                outputStream <<< "\n"
                count += 1
            }
            mutating func encodeNil() throws { emit("nil") }
            mutating func encode(_ value: Bool) throws { emit("\(value)") }
            mutating func encode(_ value: String) throws { emit("\(value)") }
            mutating func encode(_ value: Double) throws { emit("\(value)") }
            mutating func encode(_ value: Float) throws { emit("\(value)") }
            mutating func encode(_ value: Int) throws { emit("\(value)") }
            mutating func encode(_ value: Int8) throws { emit("\(value)") }
            mutating func encode(_ value: Int16) throws { emit("\(value)") }
            mutating func encode(_ value: Int32) throws { emit("\(value)") }
            mutating func encode(_ value: Int64) throws { emit("\(value)") }
            mutating func encode(_ value: UInt) throws { emit("\(value)") }
            mutating func encode(_ value: UInt8) throws { emit("\(value)") }
            mutating func encode(_ value: UInt16) throws { emit("\(value)") }
            mutating func encode(_ value: UInt32) throws { emit("\(value)") }
            mutating func encode(_ value: UInt64) throws { emit("\(value)") }
            mutating func encode<T: Encodable>(_ value: T) throws {
                let textEncoder = _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
                try value.encode(to: textEncoder)
                count += 1
                // FIXME: This is a bit arbitrary and should be controllable.  We may also want an option to only emit
                // newlines between entries, not after each one.
                if codingPath.count < 2 { outputStream <<< "\n" }
            }
            
            mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
                return KeyedEncodingContainer(PlainTextKeyedEncodingContainer<NestedKey>(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath))
            }
            
            mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
                return PlainTextUnkeyedEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
            }
            
            mutating func superEncoder() -> Encoder {
                return _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
            }
        }
        
        /// Private SingleValueEncodingContainer implementation for PlainTextEncoder.
        private struct TextSingleValueEncodingContainer: SingleValueEncodingContainer {
            let outputStream: OutputByteStream
            let formattingOptions: PlainTextEncoder.FormattingOptions
            let userInfo: [CodingUserInfoKey: Any]
            let codingPath: [CodingKey]
            
            private mutating func emit(_ value: String) {
                outputStream <<< String(repeating: "    ", count: codingPath.count)
                outputStream <<< value
                outputStream <<< "\n"
            }
            mutating func encodeNil() throws { emit("nil") }
            mutating func encode(_ value: Bool) throws { emit("\(value)") }
            mutating func encode(_ value: String) throws { emit("\(value)") }
            mutating func encode(_ value: Double) throws { emit("\(value)") }
            mutating func encode(_ value: Float) throws { emit("\(value)") }
            mutating func encode(_ value: Int) throws { emit("\(value)") }
            mutating func encode(_ value: Int8) throws { emit("\(value)") }
            mutating func encode(_ value: Int16) throws { emit("\(value)") }
            mutating func encode(_ value: Int32) throws { emit("\(value)") }
            mutating func encode(_ value: Int64) throws { emit("\(value)") }
            mutating func encode(_ value: UInt) throws { emit("\(value)") }
            mutating func encode(_ value: UInt8) throws { emit("\(value)") }
            mutating func encode(_ value: UInt16) throws { emit("\(value)") }
            mutating func encode(_ value: UInt32) throws { emit("\(value)") }
            mutating func encode(_ value: UInt64) throws { emit("\(value)") }
            mutating func encode<T: Encodable>(_ value: T) throws {
                let textEncoder = _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
                try value.encode(to: textEncoder)
            }
        }
    }
}
