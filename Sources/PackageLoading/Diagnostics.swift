/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageModel

public enum PackageBuilderDiagnostics {

    /// A target in a package contains no sources.
    public struct NoSources: DiagnosticData {
        public static let id = DiagnosticID(
            type: NoSources.self,
            name: "org.swift.diags.pkg-builder.nosources",
            defaultBehavior: .warning,
            description: {
                $0 <<< "target" <<< { "'\($0.target)'" }
                $0 <<< "in package" <<< { "'\($0.package)'" }
                $0 <<< "contains no valid source files"
            }
        )
    
        /// The name of the package.
        public let package: String

        /// The name of the target which has no sources.
        public let target: String
    }

    /// C language test target on linux is not supported.
    public struct UnsupportedCTarget: DiagnosticData {
        public static let id = DiagnosticID(
            type: UnsupportedCTarget.self,
            name: "org.swift.diags.pkg-builder.nosources",
            defaultBehavior: .warning,
            description: {
                $0 <<< "ignoring target" <<< { "'\($0.target)'" }
                $0 <<< "in package" <<< { "'\($0.package)';" }
                $0 <<< "C language in tests is not yet supported"
            }
        )

        /// The name of the package.
        public let package: String

        /// The name of the target which has no sources.
        public let target: String
    }

    public struct DuplicateProduct: DiagnosticData {
        public static let id = DiagnosticID(
            type: DuplicateProduct.self,
            name: "org.swift.diags.pkg-builder.dup-product",
            defaultBehavior: .warning,
            description: {
                $0 <<< "Ignoring duplicate product" <<< { "'\($0.product.name)'" }
                $0 <<< .substitution({
                    let `self` = $0 as! DuplicateProduct
                    switch self.product.type {
                    case .library(.automatic):
                        return ""
                    case .executable, .test: fallthrough
                    case .library(.dynamic), .library(.static):
                         return "(\(self.product.type))"
                    }
                }, preference: .default)
            }
        )

        public let product: Product
    }
}
