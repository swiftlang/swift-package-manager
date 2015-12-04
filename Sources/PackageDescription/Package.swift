/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

/// The description for a complete package.
public final class Package {
    /// The description for a package dependency.
    public class Dependency {
        public let versionRange: Range<Version>
        public let url: String

        init(_ url: String, _ versionRange: Range<Version>) {
            self.url = url
            self.versionRange = versionRange
        }

        public class func Package(url url: String, versions: Range<Version>) -> Dependency {
            return Dependency(url, versions)
        }
        public class func Package(url url: String, majorVersion: Int) -> Dependency {
            return Dependency(url, Version(majorVersion, 0, 0)..<Version(majorVersion + 1, 0, 0))
        }
        public class func Package(url url: String, majorVersion: Int, minor: Int) -> Dependency {
            return Dependency(url, Version(majorVersion, minor, 0)..<Version(majorVersion, minor + 1, 0))
        }
        public class func Package(url url: String, _ version: Version) -> Dependency {
            return Dependency(url, version...version)
        }
    }
    
    /// The name of the package, if specified.
    public let name: String?

    /// The list of targets.
    public var targets: [Target]

    /// The list of dependencies.
    public var dependencies: [Dependency]

    /// Construct a package.
    public init(name: String? = nil, targets: [Target] = [], dependencies: [Dependency] = []) {
        self.name = name
        self.targets = targets
        self.dependencies = dependencies

        // Add custom exit handler to cause package to be dumped at exit, if requested.
        //
        // FIXME: This doesn't belong here, but for now is the mechanism we use
        // to get the interpreter to dump the package when attempting to load a
        // manifest.
        if getenv("SWIFT_DUMP_PACKAGE") != nil {
            dumpPackageAtExit(self)
        }
    }

    /// Print a representation of the package as TOML.
    public func toTOML() -> String {
        var result = ""
        result += "[package]\n"
        if let name = self.name {
            result += "name = \"\(name)\"\n"
        }
        result += "dependencies = ["
        for dependency in dependencies {
            result += "[\"\(dependency.url)\", \"\(dependency.versionRange.startIndex)\", \"\(dependency.versionRange.endIndex)\"],"
        }
        result += "]\n"
        for target in targets {
            result += target.toTOML("package.targets")
        }
        return result
    }
}

extension Package : Equatable { }
public func ==(lhs: Package, rhs: Package) -> Bool {
    return (lhs.name == rhs.name &&
        lhs.targets == rhs.targets &&
        lhs.dependencies == rhs.dependencies)
}

extension Package.Dependency : Equatable { }
public func ==(lhs: Package.Dependency, rhs: Package.Dependency) -> Bool {
    return lhs.url == rhs.url && lhs.versionRange == rhs.versionRange
}

// MARK: Package Dumping

private var thePackageToDump: Package? = nil
private func dumpPackageAtExit(package: Package) {
    func dump() {
        print(thePackageToDump!.toTOML())
    }
    thePackageToDump = package
    atexit(dump)
}
