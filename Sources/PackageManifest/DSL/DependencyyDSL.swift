public protocol AnyDependency {
    var underlying: Dependency { get set }
}

// MARK: - File System Dependency

public struct FileSystem: AnyDependency {
    public var underlying: Dependency

    // FIXME: should we use URL instead of String for path?
    public init(at path: String) {
        self.underlying = Dependency(kind: .fileSystem(.init(path: path)))
    }
}

extension FileSystem {
    // FIXME: can this be made internal instead of public?
    public var settings: Dependency.FileSystemSettings {
        get {
            guard case .fileSystem(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .fileSystem(newValue)
        }
    }
}

// MARK: - Source Control Dependency

public struct SourceControl: AnyDependency {
    public var underlying: Dependency

    // FIXME: should we use URL instead of String for location?
    public init(at location: String, upToNextMajor version: Dependency.Version) {
        self.underlying = Dependency(kind: .sourceControl(.init(location: location, requirement: .range(.upToNextMajor(from: version)))))
    }

    public init(at location: String, upToNextMinor version: Dependency.Version) {
        self.underlying = Dependency(kind: .sourceControl(.init(location: location, requirement: .range(.upToNextMinor(from: version)))))
    }

    public init(at location: String, exact version: Dependency.Version) {
        self.underlying = Dependency(kind: .sourceControl(.init(location: location, requirement: .exact(version))))
    }

    public init(at location: String, revision: String) {
        self.underlying = Dependency(kind: .sourceControl(.init(location: location, requirement: .revision(revision))))
    }

    public init(at location: String, branch: String) {
        self.underlying = Dependency(kind: .sourceControl(.init(location: location, requirement: .branch(branch))))
    }
}

extension SourceControl {
    // FIXME: can this be made internal instead of public?
    public var settings: Dependency.SourceControlSettings {
        get {
            guard case .sourceControl(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .sourceControl(newValue)
        }
    }
}

// MARK: - Registry Dependency

public struct Registry: AnyDependency {
    public var underlying: Dependency

    // FIXME: should we use URL instead of String for location?
    public init(identity: String, upToNextMajor version: Dependency.Version) {
        self.underlying = Dependency(kind: .registry(.init(identity: identity, requirement: .range(.upToNextMajor(from: version)))))
    }

    public init(identity: String, upToNextMinor version: Dependency.Version) {
        self.underlying = Dependency(kind: .registry(.init(identity: identity, requirement: .range(.upToNextMinor(from: version)))))
    }

    public init(identity: String, exact version: Dependency.Version) {
        self.underlying = Dependency(kind: .registry(.init(identity: identity, requirement: .exact(version))))
    }
}

extension Registry {
    // FIXME: can this be made internal instead of public?
    public var settings: Dependency.RegistrySettings {
        get {
            guard case .registry(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .registry(newValue)
        }
    }
}
