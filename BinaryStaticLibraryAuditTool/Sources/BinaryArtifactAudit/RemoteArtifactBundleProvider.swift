package import Foundation
#if canImport(FoundationNetworking)
private import FoundationNetworking
#endif

private import SystemPackage

package struct RemoteArtifactBundleProvider: ArtifactBundleProvider {
    package init() { }

    package func artifact(for artifactURL: URL) async throws -> ArtifactBundle {
        guard let filename = FilePath(artifactURL.path).lastComponent?.stem,
            !filename.contains(".") else {
            throw Err.invalidArtifactURL(artifactURL.absoluteString)
        }

        let fileSystem = LocalFileSystem()
        let temporaryDirectoryPath = try fileSystem.createTemporaryDirectory()

        let (downloadedURL, _ ) = try await URLSession.shared.download(from: artifactURL)
        try await ZipArchiver.extract(from: FilePath(downloadedURL.path), to: temporaryDirectoryPath)

        let destination = temporaryDirectoryPath.appending(filename)
        guard fileSystem.isDirectory(destination) else {
            throw Err.failedExtraction(destination.string)
        }

        return try ArtifactBundle.create(reading: destination)
    }
}

extension RemoteArtifactBundleProvider {
    package enum Err: Error {
        case invalidArtifactURL(String)
        case failedExtraction(String)
    }
}
