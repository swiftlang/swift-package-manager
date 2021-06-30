public struct DeploymentTarget: Codable {
    public let platform: Platform
    public let version: String?

    public init(platform: Platform, version: String?) {
        self.platform = platform
        self.version = version
    }
}
