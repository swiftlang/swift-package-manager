public struct Module: Codable {
    public let name: String
    public internal (set) var kind: Kind
    public var customPath: String?

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
        self.customPath = .none
    }

    public var isPublic: Bool {
        switch self.kind {
        case .library(let settings):
            return settings.isPublic
        case .executable(let settings):
            return settings.isPublic
        case .test:
            return false // FIXME: confirm
        case .system:
            return false // FIXME: confirm
        case .binary:
            return false // FIXME: confirm
        case .plugin(let settings):
            return settings.isPublic
        }
    }

    // Sugar for programatic APIs
    public static func library(name: String, settings: LibrarySettings = .init()) -> Module {
        .init(name: name, kind: .library(settings))
    }

    // Sugar for programatic APIs
    public static func executable(name: String, settings: ExecutableSettings = .init()) -> Module {
        .init(name: name, kind: .executable(settings))
    }

    // Sugar for programatic APIs
    public static func test(name: String, settings: TestSettings = .init()) -> Module {
        .init(name: name, kind: .test(settings))
    }

    // Sugar for programatic APIs
    public static func system(name: String, settings: SystemSettings = .init()) -> Module {
        .init(name: name, kind: .system(settings))
    }

    // Sugar for programatic APIs
    public static func binary(name: String, settings: BinarySettings) -> Module {
        .init(name: name, kind: .binary(settings))
    }

    // Sugar for programatic APIs
    public static func plugin(name: String, settings: PluginSettings) -> Module {
        .init(name: name, kind: .plugin(settings))
    }
}

extension Module {
    public enum Kind: Codable {
        case library(LibrarySettings)
        case executable(ExecutableSettings)
        case test(TestSettings)
        case system(SystemSettings)
        case binary(BinarySettings)
        case plugin(PluginSettings)
    }

    public struct LibrarySettings: SourceModuleSettings, Codable {
        public var sources: [String]?
        public var resources: [String]?
        public var exclude: [String]?
        public var languageSettings: LanguageSettings?
        public var linkerSettings: [String]?
        public var isPublic: Bool = false
        public var linkage: Linkage = .auto // TBD if needed, or we want to change the model
        public var dependencies: [ModuleDependency] = [] // non-optional to make programmatic API nicer

        public init() {}

        public init(isPublic: Bool) {
            self.isPublic = isPublic
        }

        public enum Linkage: Codable {
            case auto
            case dynamic
            case `static`
        }
    }

    public struct ExecutableSettings: SourceModuleSettings, Codable {
        public var sources: [String]?
        public var resources: [String]?
        public var exclude: [String]?
        public var languageSettings: LanguageSettings?
        public var linkerSettings: [String]?
        public var isPublic: Bool = false
        public var dependencies: [ModuleDependency] = [] // non-optional to make programmatic API nicer

        public init() {}

        public init(isPublic: Bool) {
            self.isPublic = isPublic
        }
    }

    public struct TestSettings: SourceModuleSettings, Codable {
        public var sources: [String]?
        public var resources: [String]?
        public var exclude: [String]?
        public var languageSettings: LanguageSettings?
        public var linkerSettings: [String]?
        public var modules: [String] = []

        public init() {}

        public init(modules: [String]) {
            self.modules = modules
        }
    }

    public struct SystemSettings: Codable {
        var providers: [Provider]

        public init() {
            self.providers = []
        }

        public enum Provider: Codable {
            case apt([String])
            case yum([String])
            case brew([String])
        }
    }

    public struct BinarySettings: Codable {
        public var location: Location
        public var checksum: String?

        public init(path: String) {
            self.location = .fileSystem(path: path)
            self.checksum = nil
        }

        public init(url: String, checksum: String) {
            self.location = .remote(url: url)
            self.checksum = checksum
        }

        public enum Location: Codable {
            case fileSystem(path: String)
            case remote(url: String)
        }
    }

    public struct PluginSettings: Codable {
        public var capability: Capability
        public var isPublic: Bool = false

        init(capability: Capability) {
            self.capability = capability
        }

        init(capability: Capability, isPublic: Bool) {
            self.capability = capability
            self.isPublic = isPublic
        }

        public enum Capability: Codable {
            case buildTool
        }
    }
}

public protocol SourceModuleSettings {
    var sources: [String]? { get set }
    var resources: [String]? { get set }
    var exclude: [String]? { get set }
    var languageSettings: LanguageSettings? { get set }
    var linkerSettings: [String]? { get set }
}

public struct LanguageSettings: Codable {
    public var cSettings: [String]?
    public var cxxSettings: [String]?
    public var swiftSettings: [String]?
}

extension SourceModuleSettings {
    public var cSettings: [String]? {
        get {
            self.languageSettings?.cSettings
        }
        set {
            var languageSettings = self.languageSettings ?? .init()
            languageSettings.cSettings = newValue
            self.languageSettings = languageSettings
        }
    }

    public var cxxSettings: [String]? {
        get {
            self.languageSettings?.cxxSettings
        }
        set {
            var languageSettings = self.languageSettings ?? .init()
            languageSettings.cxxSettings = newValue
            self.languageSettings = languageSettings
        }
    }

    public var swiftSettings: [String]? {
        get {
            self.languageSettings?.swiftSettings
        }
        set {
            var languageSettings = self.languageSettings ?? .init()
            languageSettings.swiftSettings = newValue
            self.languageSettings = languageSettings
        }
    }
}

// MARK: - Module Dependency

public struct ModuleDependency: Codable {
    public internal (set) var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    // Sugar for programatic APIs
    public init(_ module: Module, isPublic: Bool? = nil) {
        self.init(kind: .internal(.init(name: module.name, isPublic: isPublic)))
    }

    // Sugar for programatic APIs
    public static func `internal`(name: String, isPublic: Bool? = nil) -> ModuleDependency {
        .init(kind: .internal(.init(name: name, isPublic: isPublic)))
    }

    // Sugar for programatic APIs
    public static func external(name: String, packageIdentity: String) -> ModuleDependency {
        .init(kind: .external(.init(name: name, packageIdentity: packageIdentity)))
    }
}

extension ModuleDependency {
    public enum Kind: Codable {
        case `internal`(InternalSettings)
        case external(ExternalSettings)
    }

    public struct InternalSettings: Codable {
        public var name: String
        public var isPublic: Bool

        public init(name: String, isPublic: Bool? = nil) {
            self.name = name
            self.isPublic = isPublic ?? false
        }
    }

    public struct ExternalSettings: Codable {
        public var name: String
        public var packageIdentity: String

        public init(name: String, packageIdentity: String) {
            self.name = name
            self.packageIdentity = packageIdentity
        }
    }
}
