import PackageType
import Multitool
import Get

func parseManifest(path: String, baseURL: String) throws -> Manifest {
    let swiftc = Multitool.SWIFT_EXEC
    let libdir = Multitool.libdir
    return try Manifest(path: path, baseURL: baseURL, swiftc: swiftc, libdir: libdir)
}

func fetch(_ root: String) throws -> (rootPackage: Package, externalPackages:[Package]) {
    let manifest = try parseManifest(path: root, baseURL: root)
    return try get(manifest, manifestParser: parseManifest)
}
