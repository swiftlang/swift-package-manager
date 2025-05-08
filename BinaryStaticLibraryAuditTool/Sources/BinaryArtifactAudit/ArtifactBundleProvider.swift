package import Foundation

package protocol ArtifactBundleProvider {
    func artifact(for: URL) async throws -> ArtifactBundle
}
