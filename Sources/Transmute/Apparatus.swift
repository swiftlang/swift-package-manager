import PackageType
import Utility


class Apparatus {
    let package: Package
    let srcroot: String
    private let supplementaryExcludes: [String]

    init(package: Package, supplementaryExcludes: [String]) throws {
        self.package = package
        self.supplementaryExcludes = supplementaryExcludes.map{ $0.abspath }
        self.srcroot = try determineSourceRoot(root: package.path, excluding: supplementaryExcludes + package.manifest.excludes)
    }

    var excludes: [String] {
        return supplementaryExcludes + [package.manifest.path.abspath] + package.manifest.excludes
    }
}


private func determineSourceRoot(root: String, excluding excludes: [String]) throws -> String {

    let viableRoots = walk(root, recursively: false).filter { entry in
        guard !excludes.contains(entry) else {
            return false
        }
        switch entry.basename.lowercased() {
        case "sources", "source", "src", "srcs":
            return entry.isDirectory
        default:
            return false
        }
    }

    switch viableRoots.count {
    case 0:
        return root.normpath
    case 1:
        return viableRoots[0]
    default:
        // eg. there is a `Sources' AND a `src'
        throw ModuleError.InvalidLayout(.MultipleSourceRoots(viableRoots))
    }
}


extension Manifest {
    private var excludes: [String] {
        return package.exclude.map{ Path.join(path.parentDirectory, $0).abspath }
    }
}
