import Core

public func publicFunc() -> Int {
    print("public decl")
    return PublicCore(publicVar: 10).publicVar
}

package func packageFunc() -> Int {
    print("package decl")
    return PackageCore(pkgVar: 20).pkgVar
}
