package struct ArtifactMetadata: Codable {
    package var version: String
    package var type: ArtifactType
    package var variants: [Variant]
}
