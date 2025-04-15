package import SystemPackage
private import Foundation

package struct ArtifactBundle {
    package let root: FilePath
    package let manifest: ArtifactManifest

    private init(root: FilePath, manifest: ArtifactManifest) {
        self.root = root
        self.manifest = manifest
    }

    package static func create(reading root: FilePath, in fileSystem: some FileSystem = LocalFileSystem()) throws -> ArtifactBundle {
        let manifestPath = root.appending("info.json")
        guard fileSystem.isRegularFile(manifestPath) else {
            throw Err.noManifest
        }

        let manifest = try JSONDecoder().decode(ArtifactManifest.self, from: .init(contentsOf: .init(filePath: manifestPath.string)))

        let bundle = ArtifactBundle(root: root, manifest: manifest)

        for (_, artifact) in bundle.manifest.artifacts {
            try bundle.validateMetadata(artifact, fileSystem: fileSystem)
        }

        return bundle
    }

    private func validateMetadata(_ artifact: ArtifactMetadata, fileSystem: some FileSystem) throws {
        for variant in artifact.variants {
            guard fileSystem.isRegularFile(root.appending(variant.path.components)) else {
                throw Err.noSuchVariantPath(variant.path.string)
            }

            for header in variant.headerPaths {
                guard fileSystem.isDirectory(root.appending(header.components)) else {
                    throw Err.noSuchHeaderPath(header.string)
                }
            }

            if let modulePath = variant.moduleMapPath {
                guard fileSystem.isRegularFile(root.appending(modulePath.components)) else {
                    throw Err.noSuchModuleMapPath(modulePath.string)
                }
            }
        }
    }
}

extension ArtifactBundle {
    package enum Err: Error {
        case noManifest
        case noSuchVariantPath(String)
        case noSuchHeaderPath(String)
        case noSuchModuleMapPath(String)
    }
}
