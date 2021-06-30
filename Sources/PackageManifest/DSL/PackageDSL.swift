extension Package {
    @discardableResult public func dependencies(@DependenciesBuilder _ builder: () -> [AnyDependency]) -> Package {
        let package = self
        package.dependencies = builder().map{ $0.underlying }
        return package
    }

    @discardableResult public func modules(@ModulesBuilder _ builder: () -> [AnyModule]) -> Package {
        let package = self
        package.modules = builder().map { $0.underlying }
        return package
    }

    @discardableResult public func minimumDeploymentTarget(@DeploymentTargetsBuilder _ builder: () -> [DeploymentTarget]) -> Package {
        let package = self
        package.minimumDeploymentTargets = builder()
        return package
    }
}

@resultBuilder
public enum DependenciesBuilder {
    public static func buildExpression(_ element: AnyDependency) -> [AnyDependency] {
        return [element]
    }

    public static func buildOptional(_ component: [AnyDependency]?) -> [AnyDependency] {
        return component ?? []
    }

    public static func buildEither(first component: [AnyDependency]) -> [AnyDependency] {
        return component
    }

    public static func buildEither(second component: [AnyDependency]) -> [AnyDependency] {
        return component
    }

    public static func buildArray(_ components: [[AnyDependency]]) -> [AnyDependency] {
        return components.flatMap{ $0 }
    }

    public static func buildBlock(_ components: [AnyDependency]...) -> [AnyDependency] {
        return components.flatMap{ $0 }
    }
}

@resultBuilder
public enum ModulesBuilder {
    public static func buildExpression(_ element: AnyModule) -> [AnyModule] {
        return [element]
    }

    public static func buildOptional(_ component: [AnyModule]?) -> [AnyModule] {
        return component ?? []
    }

    public static func buildEither(first component: [AnyModule]) -> [AnyModule] {
        return component
    }

    public static func buildEither(second component: [AnyModule]) -> [AnyModule] {
        return component
    }

    public static func buildArray(_ components: [[AnyModule]]) -> [AnyModule] {
        return components.flatMap{ $0 }
    }

    public static func buildBlock(_ components: [AnyModule]...) -> [AnyModule] {
        return components.flatMap{ $0 }
    }
}

@resultBuilder
public enum DeploymentTargetsBuilder {
    public static func buildExpression(_ element: DeploymentTarget) -> [DeploymentTarget] {
        return [element]
    }

    public static func buildOptional(_ component: [DeploymentTarget]?) -> [DeploymentTarget] {
        return component ?? []
    }

    public static func buildEither(first component: [DeploymentTarget]) -> [DeploymentTarget] {
        return component
    }

    public static func buildEither(second component: [DeploymentTarget]) -> [DeploymentTarget] {
        return component
    }

    public static func buildArray(_ components: [[DeploymentTarget]]) -> [DeploymentTarget] {
        return components.flatMap{ $0 }
    }

    public static func buildBlock(_ components: [DeploymentTarget]...) -> [DeploymentTarget] {
        return components.flatMap{ $0 }
    }
}
