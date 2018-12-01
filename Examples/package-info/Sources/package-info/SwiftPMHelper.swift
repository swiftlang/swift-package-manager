import Workspace

/// Helper class for working with libSwiftPM.
final class SwiftPMHelper {

    /// Path to the Swift compiler.
    static let swiftCompiler: String = {
      #if os(macOS)
        return try! Process.checkNonZeroExit(args: "xcrun", "--sdk", "macosx", "-f", "swift").spm_chomp()
      #else
        return try! Process.checkNonZeroExit(args: "which", "swift").spm_chomp()
      #endif
    }()

    /// Path of the root package.
    let rootPackage: AbsolutePath

    init(rootPackage: AbsolutePath) {
        self.rootPackage = rootPackage
    }

    /// Create a new instance of workspace.
    func createWorkspace() -> Workspace {
        return Workspace.create(
            forRootPackage: rootPackage,
            manifestLoader: createManifestLoader()
        )
    }

    /// Create a new manifest loader.
    private func createManifestLoader() -> ManifestLoader {
        let libDir = AbsolutePath(#file).appending(RelativePath("../../../.build/.bootstrap/lib/swift/pm"))

        let manifestResources = UserManifestResources(
            swiftCompiler: AbsolutePath(SwiftPMHelper.swiftCompiler), libDir: libDir)

        return ManifestLoader(
            manifestResources: manifestResources,
            isManifestSandboxEnabled: true,
            cacheDir: rootPackage.appending(component: ".build")
        )
    }
}
