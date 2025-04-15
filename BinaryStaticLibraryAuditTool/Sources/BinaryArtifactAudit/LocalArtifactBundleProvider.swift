package import Foundation
private import SystemPackage

package struct LocalArtifactBundleProvider: ArtifactBundleProvider {
    package init () { }

    package func artifact(for artifactURL: URL) async throws -> ArtifactBundle {
        let path = FilePath(artifactURL.path())
        let fileSystem = LocalFileSystem()

        guard fileSystem.isDirectory(path) else {
            throw Err.noArtifactBundle(path.string)
        }

        return try ArtifactBundle.create(reading: path, in: fileSystem)
    }
}

extension LocalArtifactBundleProvider {
    package enum Err: Error {
        case noArtifactBundle(String)
    }
}
