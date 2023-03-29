public struct PublicCore {
    public let publicVar: Int
    public init(publicVar: Int) {
        self.publicVar = publicVar
    }
}

package struct PackageCore {
    package let pkgVar: Int
    package init(pkgVar: Int) {
        self.pkgVar = pkgVar
    }
}
