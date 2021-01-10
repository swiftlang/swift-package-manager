/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import TSCBasic
import SwiftSyntax

/// An abstract location in a manifest which can be resolved to a source location.
/// Resolution is done on a best-effort basis for non-declarative manifests.
public protocol ManifestSourceLocation {
    func resolveToSourceLocation() -> SourceLocation?
}

extension DependencyDeclSourceLoc: ManifestSourceLocation {
    public func resolveToSourceLocation() -> SourceLocation? {
        let resolver = ManifestSourceLocationResolver(manifest: manifest, fileSystem: fileSystem)
        return resolver?.resolveDependencyLoc(dependency)
    }
}

private final class ManifestSourceLocationResolver {
    let manifest: Manifest
    let manifestSyntax: SourceFileSyntax
    let sourceLocationConverter: SourceLocationConverter

    init?(manifest: Manifest, fileSystem: FileSystem) {
        self.manifest = manifest
        guard let manifestContents = try? fileSystem.readFileContents(manifest.path).validDescription,
              let syntax = try? SyntaxParser.parse(source: manifestContents) else {
            return nil
        }
        self.manifestSyntax = syntax
        self.sourceLocationConverter = .init(file: manifest.path.pathString, source: manifestContents)
    }

    private func findPackageInit() -> FunctionCallExprSyntax? {
        // Find Package initializer.
        let packageFinder = PackageInitFinder()
        packageFinder.walk(manifestSyntax)
        switch packageFinder.result {
        case .found(let initFnExpr):
            return initFnExpr
        case .foundMultiple, .missing:
            return nil
        }
    }

    func resolveDependencyLoc(_ dependency: PackageDependencyDescription) -> SourceLocation? {
        guard let packageInitCall = findPackageInit() else { return nil }
        let packageDependenciesFinder = ArrayExprArgumentFinder(expectedLabel: "dependencies")
        packageDependenciesFinder.walk(packageInitCall.argumentList)
        guard case .found(let dependenciesArrayExpr) = packageDependenciesFinder.result else { return nil }
        guard let element = dependenciesArrayExpr.elements.first(where: { element in
            guard let callExpr = element.expression.as(FunctionCallExprSyntax.self),
                  let memberExpr = callExpr.calledExpression.as(MemberAccessExprSyntax.self),
                  memberExpr.base == nil,
                  memberExpr.name.tokenKind == .identifier("package") else { return false }

            guard let urlOrPathElement = callExpr.argumentList.first(where: {
                $0.label?.tokenKind == .identifier("url") || $0.label?.tokenKind == .identifier("path")
            }) else { return false }

            guard let urlOrPathLiteral = urlOrPathElement.expression.as(StringLiteralExprSyntax.self),
                  urlOrPathLiteral.segments.count == 1 else { return false }

            let urlOrPathTokens = Array(urlOrPathLiteral.segments.first!.tokens)

            guard urlOrPathTokens.count == 1,
                  case .stringSegment(let urlOrPath) = urlOrPathTokens[0].tokenKind else { return false }

            // FIXME: SwiftPM can't handle file URLs with file:// scheme so we need to
            // strip that. We need to design a URL data structure for SwiftPM.
            let filePrefix = "file://"
            let normalizedURL: String
            if urlOrPath.hasPrefix(filePrefix) {
                normalizedURL = AbsolutePath(String(urlOrPath.dropFirst(filePrefix.count))).pathString
            } else {
                normalizedURL = urlOrPath
            }
            
            return normalizedURL == dependency.url
        }) else { return nil }
        return element.startLocation(converter: sourceLocationConverter)
    }

}
