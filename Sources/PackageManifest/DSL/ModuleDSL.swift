public protocol AnyModule {
    var underlying: Module { get set }
    var name: String { get }
}

extension AnyModule {
    public var name: String {
        return self.underlying.name
    }
}

extension AnyModule {
    public func customPath(_ path: String) -> Self {
        var module = self
        module.underlying.customPath = path
        return module
    }
}

// MARK: - Sources Module (base abstraction)

public protocol SourcesModule: AnyModule {
    associatedtype Settings: SourceModuleSettings
    var settings: Settings { get set }
}

extension SourcesModule  {
    public func sources(_ value: String ...) -> Self {
        var module = self
        module.settings.sources = value
        return module
    }

    public func exclude(_ value: String ...) -> Self {
        var module = self
        module.settings.exclude = value
        return module
    }

    public func swiftSettings(_ value: String ...) -> Self {
        var module = self
        module.settings.swiftSettings = value
        return module
    }

    public func cSettings(_ value: String ...) -> Self {
        var module = self
        module.settings.cSettings = value
        return module
    }

    public func cxxSettings(_ value: String ...) -> Self {
        var module = self
        module.settings.cxxSettings = value
        return module
    }
}

// MARK: - Library Module

public struct Library: SourcesModule {
    public var underlying: Module

    public init(_ name: String, public isPublic: Bool = false) {
        self.underlying = Module(name: name, kind: .library(.init(isPublic: isPublic)))
    }

    public func include(@ModuleDependenciesBuilder _ builder: () -> [AnyModuleDependency]) -> Self {
        var module = self
        module.settings.dependencies = builder().flatMap { $0.underlying }
        return module
    }

    // FIXME: can this be made internal instead of public?
    public var settings: Module.LibrarySettings {
        get {
            guard case .library(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .library(newValue)
        }
    }
}

// MARK: - Executable Module

public struct Executable: SourcesModule {
    public var underlying: Module

    public init(_ name: String, public isPublic: Bool = false) {
        self.underlying = Module(name: name, kind: .executable(.init(isPublic: isPublic)))
    }

    public func include(@ModuleDependenciesBuilder _ builder: () -> [AnyModuleDependency]) -> Self {
        var module = self
        module.settings.dependencies = builder().flatMap { $0.underlying }
        return module
    }

    // FIXME: can this be made internal instead of public?
    public var settings: Module.ExecutableSettings {
        get {
            guard case .executable(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .executable(newValue)
        }
    }
}

// MARK: - Test Module

public struct Test: SourcesModule {
    public var underlying: Module

    public init(_ name: String, for module: String) {
        self.underlying = Module(name: name, kind: .test(.init(modules: [module])))
    }

    public init(_ name: String, for module: AnyModule) {
        self.init(name, for: module.name)
    }

    public func include(modules: [String]) -> Self {
        var module = self
        module.settings.modules.append(contentsOf: modules)
        return module
    }

    public func include(_ modules: String ...) -> Self {
        self.include(modules: modules)
    }

    public func include(_ modules: Module ...) -> Self {
        let moduleNames = modules.map(\.name)
        return self.include(modules: moduleNames)
    }

    // FIXME: can this be made internal instead of public?
    public var settings: Module.TestSettings {
        get {
            guard case .test(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .test(newValue)
        }
    }
}

// MARK: - Binary Module

public struct Binary: AnyModule {
    public var underlying: Module

    public init(_ name: String, path: String) {
        self.underlying = Module(
            name: name,
            kind: .binary(
                .init(path: path)
            )
        )
    }

    public init(_ name: String, url: String, checksum: String) {
        self.underlying = Module(
            name: name,
            kind: .binary(
                .init(url: url, checksum: checksum)
            )
        )
    }

    // FIXME: can this be made internal instead of public?
    public var settings: Module.BinarySettings {
        get {
            guard case .binary(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .binary(newValue)
        }
    }
}

// MARK: - Plugin Module

public struct Plugin: AnyModule {
    public var underlying: Module

    public init(
        _ name: String,
        capability: Module.PluginSettings.Capability,
        public isPublic: Bool = false
    ) {
        self.underlying = Module(
            name: name,
            kind: .plugin(
                .init(
                    capability: capability,
                    isPublic: isPublic
                )
            )
        )
    }

    // FIXME: can this be made internal instead of public?
    public var settings: Module.PluginSettings {
        get {
            guard case .plugin(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .plugin(newValue)
        }
    }
}

// MARK: - System Module

public struct System: AnyModule {
    public var underlying: Module

    public init(_ name: String) {
        self.underlying = Module(
            name: name,
            kind: .system(.init())
        )
    }

    public func providers(@SystemModuleProvidersBuilder _ builder: () -> [AnySystemModuleProvider]) -> Self {
        var module = self
        module.settings.providers = builder().map { $0.underlying }
        return module
    }

    // FIXME: can this be made internal instead of public?
    public var settings: Module.SystemSettings {
        get {
            guard case .system(let settings) = self.underlying.kind else {
                preconditionFailure("invalid type") // programmer error
            }
            return settings
        }
        set {
            self.underlying.kind = .system(newValue)
        }
    }
}

// MARK: - Module dependencies

@resultBuilder
public enum ModuleDependenciesBuilder {
    public static func buildExpression(_ module: AnyModuleDependency) -> [AnyModuleDependency] {
        return [module]
    }

    public static func buildExpression(_ module: AnyModule) -> [AnyModuleDependency] {
        return [Internal(module)]
    }

    public static func buildExpression(_ pair: (AnyModule, `public`: Bool)) -> [AnyModuleDependency] {
        return [Internal(pair.0, public: pair.1)]
    }

    public static func buildExpression(_ moduleName: String) -> [AnyModuleDependency] {
        return [Internal(moduleName)]
    }

    public static func buildOptional(_ component: [AnyModuleDependency]?) -> [AnyModuleDependency] {
        return component ?? []
    }

    public static func buildEither(first component: [AnyModuleDependency]) -> [AnyModuleDependency] {
        return component
    }

    public static func buildEither(second component: [AnyModuleDependency]) -> [AnyModuleDependency] {
        return component
    }

    public static func buildArray(_ components: [[AnyModuleDependency]]) -> [AnyModuleDependency] {
        return components.flatMap{ $0 }
    }

    public static func buildBlock(_ components: [AnyModuleDependency]...) -> [AnyModuleDependency] {
        return components.flatMap{ $0 }
    }
}

public protocol AnyModuleDependency {
    var underlying: [ModuleDependency] { get set }
}

public struct Internal: AnyModuleDependency {
    public var underlying: [ModuleDependency]

    public init(_ name: String, public isPublic: Bool? = nil) {
        self.underlying = [ModuleDependency(kind: .internal(.init(name: name, isPublic: isPublic)))]
    }

    public init(_ names: [String]) {
        self.underlying = names.map { ModuleDependency(kind: .internal(.init(name: $0))) }
    }

    public init(_ module: AnyModule, public isPublic: Bool? = nil) {
        self.underlying = [ModuleDependency(module.underlying, isPublic: isPublic)]
    }
}

public struct External: AnyModuleDependency {
    public var underlying: [ModuleDependency]

    public init(_ name: String, from: String) {
        self.underlying = [ModuleDependency(kind: .external(.init(name: name, packageIdentity: from)))]
    }

    /* TODO: packageIdentity from AnyDependency
    public init(_ name: String, from: AnyDependency) {
        self.underlying = [ModuleDependency(kind: .external(.init(name: name, packageIdentity: from.underlying.)))]
    }*/
}

// MARK: - System Module provider

@resultBuilder
public enum SystemModuleProvidersBuilder {
    public static func buildExpression(_ element: AnySystemModuleProvider) -> [AnySystemModuleProvider] {
        return [element]
    }

    public static func buildOptional(_ component: [AnySystemModuleProvider]?) -> [AnySystemModuleProvider] {
        return component ?? []
    }

    public static func buildEither(first component: [AnySystemModuleProvider]) -> [AnySystemModuleProvider] {
        return component
    }

    public static func buildEither(second component: [AnySystemModuleProvider]) -> [AnySystemModuleProvider] {
        return component
    }

    public static func buildArray(_ components: [[AnySystemModuleProvider]]) -> [AnySystemModuleProvider] {
        return components.flatMap{ $0 }
    }

    public static func buildBlock(_ components: [AnySystemModuleProvider]...) -> [AnySystemModuleProvider] {
        return components.flatMap{ $0 }
    }
}

public protocol AnySystemModuleProvider {
    var underlying: Module.SystemSettings.Provider { get set }
}

public struct apt: AnySystemModuleProvider {
    public var underlying: Module.SystemSettings.Provider

    public init(_ packages: String ...) {
        self.underlying = .apt(packages)
    }
}

public struct yum: AnySystemModuleProvider {
    public var underlying: Module.SystemSettings.Provider

    public init(_ packages: String ...) {
        self.underlying = .yum(packages)
    }
}

public struct brew: AnySystemModuleProvider {
    public var underlying: Module.SystemSettings.Provider

    public init(_ packages: String ...) {
        self.underlying = .brew(packages)
    }
}
