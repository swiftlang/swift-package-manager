/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import PackageDescription

extension PackageDescription.Package {
    public static func fromTOML(item: TOMLItem, baseURL: String? = nil) -> PackageDescription.Package {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .Table(let topLevelTable) = item else { fatalError("unexpected item") }
        guard case .Table(let table)? = topLevelTable.items["package"] else { fatalError("missing package") }

        var name: String? = nil
        if case .String(let value)? = table.items["name"] {
            name = value
        }

        // Parse the targets.
        var targets: [PackageDescription.Target] = []
        if case .Array(let array)? = table.items["targets"] {
            for item in array.items {
                targets.append(PackageDescription.Target.fromTOML(item))
            }
        }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Package.Dependency] = []
        if case .Array(let array)? = table.items["dependencies"] {
            for item in array.items {
                dependencies.append(PackageDescription.Package.Dependency.fromTOML(item, baseURL: baseURL))
            }
        }

        // Parse the test dependencies.
        var testDependencies: [PackageDescription.Package.Dependency] = []
        if case .Array(let array)? = table.items["testDependencies"] {
            for item in array.items {
                testDependencies.append(PackageDescription.Package.Dependency.fromTOML(item, baseURL: baseURL))
            }
        }

        //Parse the exclude folders.
        var exclude: [String] = []
        if case .Array(let array)? = table.items["exclude"] {
            for item in array.items {
                guard case .String(let excludeItem) = item else { fatalError("exclude contains non string element") }
                exclude.append(excludeItem)
            }
        }
        
        return PackageDescription.Package(name: name, targets: targets, dependencies: dependencies, testDependencies: testDependencies, exclude: exclude)
    }
}

extension PackageDescription.Package.Dependency {
    public static func fromTOML(item: TOMLItem, baseURL: String?) -> PackageDescription.Package.Dependency {
        guard case .Array(let array) = item where array.items.count == 3 else {
            fatalError("Unexpected TOMLItem")
        }
        guard case .String(let url) = array.items[0],
              case .String(let vv1) = array.items[1],
              case .String(let vv2) = array.items[2],
              let v1 = Version(vv1), v2 = Version(vv2)
        else {
            fatalError("Unexpected TOMLItem")
        }

        func fixURL() -> String {
            if let baseURL = baseURL where URL.scheme(url) == nil {
                return Path.join(baseURL, url).normpath
            } else {
                return url
            }
        }

        return PackageDescription.Package.Dependency.Package(url: fixURL(), versions: v1..<v2)
    }
}

extension PackageDescription.Target {
    private static func fromTOML(item: TOMLItem) -> PackageDescription.Target {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .Table(let table) = item else { fatalError("unexpected item") }

        guard case .String(let name)? = table.items["name"] else { fatalError("missing name") }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Target.Dependency] = []
        if case .Array(let array)? = table.items["dependencies"] {
            for item in array.items {
                dependencies.append(PackageDescription.Target.Dependency.fromTOML(item))
            }
        }
        
        return PackageDescription.Target(name: name, dependencies: dependencies)
    }
}

extension PackageDescription.Target.Dependency {
    private static func fromTOML(item: TOMLItem) -> PackageDescription.Target.Dependency {
        guard case .String(let name) = item else { fatalError("unexpected item") }
        return .Target(name: name)
    }
}


extension PackageDescription.Product {
    private init(toml item: TOMLItem) {
        guard case .Table(let table) = item else { fatalError("unexpected item") }
        guard case .String(let name)? = table.items["name"] else { fatalError("missing name") }

        let type: ProductType
        switch table.items["type"] {
        case .String("exe")?:
            type = .Executable
        case .String("a")?:
            type = .Library(.Static)
        case .String("dylib")?:
            type = .Library(.Dynamic)
        case .String("test")?:
            type = .Test
        default:
            fatalError("missing type")
        }

        guard case .Array(let mods)? = table.items["mods"] else { fatalError("missing mods") }

        let modules = mods.items.map { item -> String in
            guard case TOMLItem.String(let string) = item else { fatalError("invalid modules") }
            return string
        }

        self.init(name: name, type: type, modules: modules)
    }

    public static func fromTOML(item: TOMLItem) -> [PackageDescription.Product] {
        guard case .Table(let root) = item else { fatalError("unexpected item") }
        guard let productsItem = root.items["products"] else { return [] }
        guard case .Array(let array) = productsItem else { fatalError("products wrong type") }
        return array.items.map(Product.init)
    }
}
