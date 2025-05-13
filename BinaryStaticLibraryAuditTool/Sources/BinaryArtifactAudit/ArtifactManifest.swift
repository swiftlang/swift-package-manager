package struct ArtifactManifest: Codable {
    package var schemaVersion: String
    package var artifacts: [String: ArtifactMetadata]
}
