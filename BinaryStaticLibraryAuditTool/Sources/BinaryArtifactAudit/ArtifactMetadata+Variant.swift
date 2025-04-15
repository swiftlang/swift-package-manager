package import SystemPackage

extension ArtifactMetadata {
    package struct Variant: Codable {
        package var path: FilePath
        package var headerPaths: [FilePath]
        package var moduleMapPath: FilePath? = nil
        package var supportedTriples: [String]

        enum CodingKeys: String, CodingKey {
            case path
            case headerPaths
            case moduleMapPath
            case supportedTriples
        }

        package func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path.string , forKey: .path)
            try container.encode(headerPaths.map { $0.string }, forKey: .headerPaths)
            try container.encodeIfPresent(moduleMapPath.map { $0.string }, forKey: .moduleMapPath)
            try container.encode(supportedTriples, forKey: .supportedTriples)
        }

        package init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)

            let pathString = try values.decode(String.self, forKey: .path)
            self.path = FilePath(pathString)

            let headerPathStrings = try values.decode([String].self, forKey: .headerPaths)
            self.headerPaths = headerPathStrings.map { FilePath($0) }

            let moduleMapPathString = try values.decodeIfPresent(String.self, forKey: .moduleMapPath)
            self.moduleMapPath = moduleMapPathString.map { FilePath($0) }

            self.supportedTriples = try values.decode([String].self, forKey: .supportedTriples)
        }
    }
}
