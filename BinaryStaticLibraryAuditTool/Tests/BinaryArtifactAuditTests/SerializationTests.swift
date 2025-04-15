internal import Testing

private import BinaryArtifactAudit

private import Foundation
private import SystemPackage

@Suite("Artifact manifest serialization")
struct ManifestSerializationTests {
    @Test("Decode")
    func decodeSampleManifest() throws {
        let sampleManifest = """
        {
            "schemaVersion": "1.0",
            "artifacts": {
                "first": {
                    "version": "0.1.0",
                    "type": "staticLibrary",
                    "variants": [
                        {
                            "path": "first-0.1.0-linux/lib/first.a",
                            "headerPaths": ["include/"],
                            "moduleMapPath": "include/first.modulemap",
                            "supportedTriples": ["x86_64-unknown-linux-gnu"]
                        },
                        {
                            "path": "first-0.1.0-macos/lib/first.a",
                            "headerPaths": ["include/"],
                            "moduleMapPath": "include/first.modulemap",
                            "supportedTriples": ["x86_64-apple-macosx", "arm64-apple-macosx"]
                        },
                        {
                            "path": "first-0.1.0-windows/lib/first.lib",
                            "headerPaths": ["include/"],
                            "moduleMapPath": "include/first.modulemap",
                            "supportedTriples": ["x86_64-unknown-windows"]
                        }
                    ]
                },
                "second": {
                    "version": "1.0.0",
                    "type": "staticLibrary",
                    "variants": [
                        {
                            "path": "second-1.0.0-linux/lib/second.a",
                            "headerPaths": ["include/"],
                            "supportedTriples": ["x86_64-unknown-linux-gnu"]
                        }
                    ]
                }
            }
        }
        """
        let encodedManifest = try #require(sampleManifest.data(using: .utf8))

        let manifest = try JSONDecoder().decode(ArtifactManifest.self, from: encodedManifest)
        #expect(manifest.schemaVersion == "1.0")
        #expect(Array(manifest.artifacts.keys).sorted() == ["first", "second"])

        let firstArtifact = try #require(manifest.artifacts["first"])
        #expect(firstArtifact.version == "0.1.0")
        #expect(firstArtifact.type == .staticLibrary)
        #expect(firstArtifact.variants.count == 3)
        #expect(firstArtifact.variants[0].path == FilePath("first-0.1.0-linux/lib/first.a"))
        #expect(firstArtifact.variants[0].headerPaths == [FilePath("include/")])
        #expect(firstArtifact.variants[0].moduleMapPath == FilePath("include/first.modulemap"))
        #expect(firstArtifact.variants[0].supportedTriples == ["x86_64-unknown-linux-gnu"])

        #expect(firstArtifact.variants[1].path == FilePath("first-0.1.0-macos/lib/first.a"))
        #expect(firstArtifact.variants[1].headerPaths == [FilePath("include/")])
        #expect(firstArtifact.variants[1].moduleMapPath == FilePath("include/first.modulemap"))
        #expect(firstArtifact.variants[1].supportedTriples.sorted() == ["arm64-apple-macosx", "x86_64-apple-macosx"])

        #expect(firstArtifact.variants[2].path == FilePath("first-0.1.0-windows/lib/first.lib"))
        #expect(firstArtifact.variants[2].headerPaths == [FilePath("include/")])
        #expect(firstArtifact.variants[2].moduleMapPath == FilePath("include/first.modulemap"))
        #expect(firstArtifact.variants[2].supportedTriples == ["x86_64-unknown-windows"])

        let secondArtifact = try #require(manifest.artifacts["second"])
        #expect(secondArtifact.version == "1.0.0")
        #expect(secondArtifact.type == .staticLibrary)
        #expect(secondArtifact.variants.count == 1)
        #expect(secondArtifact.variants[0].path == FilePath("second-1.0.0-linux/lib/second.a"))
        #expect(secondArtifact.variants[0].headerPaths == [FilePath("include/")])
        #expect(secondArtifact.variants[0].moduleMapPath == nil)
        #expect(secondArtifact.variants[0].supportedTriples == ["x86_64-unknown-linux-gnu"])
    }

}
