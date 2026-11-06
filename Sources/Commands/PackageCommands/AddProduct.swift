//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageGraph
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax
import TSCBasic
import TSCUtility
import Workspace

extension SwiftPackageCommand {
    struct AddProduct: SwiftCommand {
        /// The package product type used for the command-line. This is a
        /// subset of `ProductType` that expands out the library types.
        enum CommandProductType: String, Codable, ExpressibleByArgument, CaseIterable {
            case executable
            case library
            case staticLibrary = "static-library"
            case dynamicLibrary = "dynamic-library"
            case plugin
        }

        package static let configuration = CommandConfiguration(
            abstract: "Add a new product to the manifest.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The name of the new product.")
        var name: String

        @Option(help: "The type of target to add.")
        var type: CommandProductType = .library

        @Option(
            parsing: .upToNextOption,
            help: "A list of targets that are part of this product."
        )
        var targets: [String] = []

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let (manifestSyntax, manifestPath) = try swiftCommandState.readPackageManifestAsSyntaxTree()

            // Map the product type.
            let type: ProductDescription.ProductType = switch self.type {
            case .executable: .executable
            case .library: .library(.automatic)
            case .dynamicLibrary: .library(.dynamic)
            case .staticLibrary: .library(.static)
            case .plugin: .plugin
            }

            let product = ProductDescription(
                name: name,
                type: type,
                targets: targets
            )

            let editResult = try SwiftRefactor.AddProduct.textRefactor(
                syntax: manifestSyntax,
                in: .init(product: product)
            )

            try editResult.applyEdits(
                to: swiftCommandState.getActiveWorkspace().fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !globalOptions.logging.quiet
            )
        }
    }
}
