public func MacOS(_ version: String? = nil) -> DeploymentTarget  {
    .init(platform: .macOS, version: version)
}

public func iOS(_ version: String? = nil) -> DeploymentTarget  {
    .init(platform: .iOS, version: version)
}
