/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Represents a single package in the graph (either the root or a dependency).
public class Package {
    /// The name of the package (for display purposes only).
    public let name: String

    /// The absolute path of the package directory in the local file system.
    public let directory: Path

    /// Any dependencies on other packages, in the same order as they are
    /// specified in the package manifest.
    public let dependencies: [Dependency]

    /// Represents a resolved dependency of a package on another package. This is a
    /// separate entity in order to make it easier for future versions of the API to
    /// add information about the dependency itself.
    public struct Dependency {
        /// The package to which the dependency was resolved.
        public let package: Package
        
        init(package: Package) {
            self.package = package
        }
    }

    /// Any regular products defined in this package (except plugin products),
    /// in the same order as they are specified in the package manifest.
    public let products: [Product]

    /// Any regular targets defined in this package (except plugin targets),
    /// in the same order as they are specified in the package manifest.
    public let targets: [Target]
    
    init(name: String, directory: Path, dependencies: [Dependency], products: [Product], targets: [Target]) {
        self.name = name
        self.directory = directory
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
    }
}

/// Represents a single product defined in a package. Specializations represent
/// different types of products.
public class Product {
    /// The name of the product, as defined in the package manifest. It's unique
    /// among the products of the package in which it is defined.
    public let name: String
    
    /// The targets that directly comprise the product, in the order in which
    /// they are declared in the package manifest. The product will contain the
    /// transitive closure of the these targets and their depdendencies.
    public let targets: [Target]

    init(name: String, targets: [Target]) {
        self.name = name
        self.targets = targets
    }
}

/// Represents an executable product defined in a package.
public class ExecutableProduct: Product {
    /// The target that contains the main entry point of the executable. Every
    /// executable product has exactly one main executable target. This target
    /// will always be one of the targets in the product's `targets` array.
    public let mainTarget: Target

    init(name: String, targets: [Target], mainTarget: Target) {
        self.mainTarget = mainTarget
        super.init(name: name, targets: targets)
    }
}

/// Represents a library product defined in a package.
public class LibraryProduct: Product {
    /// Whether the library is static, dynamic, or automatically determined.
    public let type: LibraryType

    init(name: String, targets: [Target], type: LibraryType) {
        self.type = type
        super.init(name: name, targets: targets)
    }
}

/// A type of library product.
public enum LibraryType {
    /// Static library.
    case `static`

    /// Dynamic library.
    case `dynamic`

    /// The type of library is unspecified and will be determined at build time.
    case automatic
}

/// Represents a single target defined in a package. Specializations represent
/// different types of targets.
public class Target {
    /// The name of the target, as defined in the package manifest. It's unique
    /// among the targets of the package.
    public var name: String
    
    /// The absolute path of the target directory in the local file system.
    public var directory: Path
    
    /// Any other targets on which this target depends, in the same order as
    /// they are specified in the package manifest. Conditional dependencies
    /// that do not apply have already been filtered out.
    public var dependencies: [Dependency]

    /// Represents a dependency of a target on a product or on another target.
    public enum Dependency {
        /// A dependency on a target in the same package.
        case target(Target)

        /// A dependency on a product in another package.
        case product(Product)
    }

    init(name: String, directory: Path, dependencies: [Dependency]) {
        self.name = name
        self.directory = directory
        self.dependencies = dependencies
    }
}

/// Represents a target consisting of a source code module, containing either
/// Swift or source files in one of the C-based languages.
public class SourceModuleTarget: Target {
    /// The name of the module produced by the target (derived from the target
    /// name, though future SwiftPM versions may allow this to be customized).
    public var moduleName: String

    /// The directory containing public C headers, if applicable. This will
    /// only be set for targets that have Clang sources, and only if there is
    /// a public headers directory.
    public var publicHeadersDirectory: Path?

    /// The source files that are associated with this target (any files that
    /// have been excluded in the manifest have already been filtered out).
    public var sourceFiles: FileList

   init(name: String, directory: Path, dependencies: [Dependency], moduleName: String, publicHeadersDirectory: Path?, sourceFiles: FileList) {
        self.moduleName = moduleName
        self.sourceFiles = sourceFiles
        self.publicHeadersDirectory = publicHeadersDirectory
        super.init(name: name, directory: directory, dependencies: dependencies)
    }
}

/// Represents a target describing a library that is distributed as a binary.
public class BinaryLibraryTarget: Target {
    /// The binary library path, having a filename suffix of `.xcframeworks`.
    public var libraryPath: Path

    init(name: String, directory: Path, dependencies: [Dependency], libraryPath: Path) {
        self.libraryPath = libraryPath
        super.init(name: name, directory: directory, dependencies: dependencies)
    }
}

/// Represents a target describing a system library that is expected to be
/// present on the host system.
public class SystemLibraryTarget: Target {
    /// The directory containing public C headers, if applicable.
    public let publicHeadersDirectory: Path?

    init(name: String, directory: Path, dependencies: [Dependency], publicHeadersDirectory: Path?) {
        self.publicHeadersDirectory = publicHeadersDirectory
        super.init(name: name, directory: directory, dependencies: dependencies)
    }
}

/// Provides information about a list of files. The order is not defined
/// but is guaranteed to be stable. This allows the implementation to be
/// more efficient than a static file list.
public struct FileList {
    private var files: [File]

    init(_ files: [File]) {
        self.files = files
    }
}
extension FileList: Sequence {
    public struct Iterator: IteratorProtocol {
        private var files: ArraySlice<File>
        fileprivate init(files: ArraySlice<File>) {
            self.files = files
        }
        mutating public func next() -> File? {
            guard let nextInfo = self.files.popFirst() else {
                return nil
            }
            return nextInfo
        }
    }
    public func makeIterator() -> Iterator {
        return Iterator(files: ArraySlice(self.files))
    }
}

/// Provides information about a single file in a FileList.
public struct File {
    /// The path of the file.
    public let path: Path
    
    /// File type, as determined by SwiftPM.
    public let type: FileType
}

/// Provides information about the type of a file. Any future cases will
/// use availability annotations to make sure existing plugins still work
/// until they increase their required tools version.
public enum FileType {
    /// A source file.
    case source

    /// A header file.
    case header

    /// A resource file (either processed or copied).
    case resource

    /// A file not covered by any other rule.
    case unknown
}

extension Target {
    /// The transitive closure of all the targets on which the reciver depends,
    /// ordered such that every dependency appears before any other target that
    /// depends on it (i.e. in "topological sort order").
    public var recursiveTargetDependencies: [Target] {
        // FIXME: We can rewrite this to use a stack instead of recursion.
        var result = [Target]()
        var visited = Set<ObjectIdentifier>()
        func visit(target: Target) {
            guard !visited.insert(ObjectIdentifier(target)).inserted else { return }
            target.dependencies.forEach{ visit(dependency: $0) }
            result.append(target)
        }
        func visit(dependency: Target.Dependency) {
            switch dependency {
            case .target(let target):
                visit(target: target)
            case .product(let product):
                product.targets.forEach{ visit(target: $0) }
            }
        }
        return result
    }
}
