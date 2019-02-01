/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SwiftSyntax

/// A package manifest rewriter.
///
/// This class provides functionality for rewriting the
/// Swift package manifest using the SwiftSyntax library.
///
/// Similar to SwiftSyntax, this class only deals with the
/// syntax and has no functionality for semantics of the manifest.
public final class ManifestRewriter {

    enum Error: Swift.Error {
        case error(String)
    }

    /// The contents of the original manifest.
    public let originalManifest: String

    /// The contents of the edited manifest.
    public var editedManifest: String {
        return editedSource.description
    }

    /// The edited manifest syntax.
    private var editedSource: Syntax

    /// Create a new manfiest editor with the given contents.
    public init(_ manifest: String) throws {
        self.originalManifest = manifest
        self.editedSource = try SyntaxParser.parse(source: manifest)
    }

    /// Add a package dependency.
    public func addPackageDependency(
        url: String,
        requirement: PackageDependencyRequirement
    ) throws {
        // Find Package initializer.
        let packageFinder = PackageInitFinder()
        editedSource.walk(packageFinder)

        guard let initFnExpr = packageFinder.packageInit else {
            throw Error.error("Couldn't find Package initializer")
        }

        // Find dependencies section in the argument list of Package(...).
        let packageDependenciesFinder = DependenciesArrayFinder()
        initFnExpr.argumentList.walk(packageDependenciesFinder)

        let packageDependencies: ArrayExprSyntax
        if let existingPackageDependencies = packageDependenciesFinder.dependenciesArrayExpr {
            packageDependencies = existingPackageDependencies
        } else {
            // We didn't find a dependencies section so insert one.
            let argListWithDependencies = DependenciesArrayWriter().visit(initFnExpr.argumentList)

            // Find the inserted section.
            let packageDependenciesFinder = DependenciesArrayFinder()
            argListWithDependencies.walk(packageDependenciesFinder)
            packageDependencies = packageDependenciesFinder.dependenciesArrayExpr!
        }

        // Add the the package dependency entry.
       let newManifest = PackageDependencyWriter(
            url: url,
            requirement: requirement
        ).visit(packageDependencies).root

        self.editedSource = newManifest
    }

    /// Add a target dependency.
    public func addTargetDependency(
        target: String,
        dependency: String
    ) throws {
        // Find Package initializer.
        let packageFinder = PackageInitFinder()
        editedSource.walk(packageFinder)

        guard let initFnExpr = packageFinder.packageInit else {
            throw Error.error("Couldn't find Package initializer")
        }

        // Find the `targets: []` array.
        let targetsArrayFinder = TargetsArrayFinder()
        initFnExpr.argumentList.walk(targetsArrayFinder)
        guard let targetsArrayExpr = targetsArrayFinder.targets else {
            throw Error.error("Couldn't find targets label")
        }

        // Find the target node.
        let targetFinder = TargetFinder(name: target)
        targetsArrayExpr.walk(targetFinder)
        guard let targetNode = targetFinder.foundTarget else {
            throw Error.error("Couldn't find target \(target)")
        }

        let targetDependencyFinder = DependenciesArrayFinder()
        targetNode.walk(targetDependencyFinder)

        guard let targetDependencies = targetDependencyFinder.dependenciesArrayExpr else {
            throw Error.error("Couldn't find dependencies section")
        }

        // Add the target dependency entry.
        let newManifest = TargetDependencyWriter(
            dependencyName: dependency
        ).visit(targetDependencies).root

        self.editedSource = newManifest
    }

    /// Add a new target.
    public func addTarget(
        targetName: String,
        type: TargetType = .regular
    ) throws {
        // Find Package initializer.
        let packageFinder = PackageInitFinder()
        editedSource.walk(packageFinder)

        guard let initFnExpr = packageFinder.packageInit else {
            throw Error.error("Couldn't find Package initializer")
        }

        let targetsFinder = TargetsArrayFinder()
        initFnExpr.argumentList.walk(targetsFinder)

        guard let targetsNode = targetsFinder.targets else {
            throw Error.error("Couldn't find targets section")
        }

        let newManifest = NewTargetWriter(
            name: targetName, targetType: type
        ).visit(targetsNode).root

        self.editedSource = newManifest
    }
}

// MARK: - Syntax Visitors

/// Package init finder.
final class PackageInitFinder: SyntaxVisitor {

    /// Reference to the function call of the package initializer.
    private(set) var packageInit: FunctionCallExprSyntax?

    override func shouldVisit(_ kind: SyntaxKind) -> Bool {
        return kind == .initializerClause
    }

    override func visit(_ node: InitializerClauseSyntax) -> SyntaxVisitorContinueKind {
        if let fnCall = node.value as? FunctionCallExprSyntax,
            let identifier = fnCall.calledExpression.firstToken,
            identifier.text == "Package" {
            assert(packageInit == nil, "Found two package initializers")
            packageInit = fnCall
        }
        return .skipChildren
    }
}

/// Finder for "dependencies" array syntax.
final class DependenciesArrayFinder: SyntaxVisitor {

    private(set) var dependenciesArrayExpr: ArrayExprSyntax?

    override func visit(_ node: FunctionCallArgumentSyntax) -> SyntaxVisitorContinueKind {
        guard node.label?.text == "dependencies" else {
            return .skipChildren
        }

        // We have custom code like foo + bar + [] (hopefully there is an array expr here).
        if let seq = node.expression as? SequenceExprSyntax {
            dependenciesArrayExpr = seq.elements.first(where: { $0 is ArrayExprSyntax }) as? ArrayExprSyntax
        } else if let arrayExpr = node.expression as? ArrayExprSyntax {
            dependenciesArrayExpr = arrayExpr
        }

        // FIXME: If we find a dependencies section but not an array expr, then we should
        // not try to insert one later. i.e. return error if depsArray is nil.

        return .skipChildren
    }
}

/// Finder for targets array expression.
final class TargetsArrayFinder: SyntaxVisitor {

    /// The found targets array expr.
    private(set) var targets: ArrayExprSyntax?

    override func visit(_ node: FunctionCallArgumentSyntax) -> SyntaxVisitorContinueKind {
        if node.label?.text == "targets",
            let expr = node.expression as? ArrayExprSyntax {
            assert(targets == nil, "Found two targets labels")
            targets = expr
        }
        return .skipChildren
    }
}

/// Finds a given target in a list of targets.
final class TargetFinder: SyntaxVisitor {

    let targetToFind: String
    private(set) var foundTarget: FunctionCallArgumentListSyntax?

    init(name: String) {
        self.targetToFind = name
    }

    override func visit(_ node: FunctionCallArgumentSyntax) -> SyntaxVisitorContinueKind {
        guard case .identifier(let label)? = node.label?.tokenKind else {
            return .skipChildren
        }
        guard label == "name", let targetNameExpr = node.expression as? StringLiteralExprSyntax else {
            return .skipChildren
        }
        guard case .stringLiteral(let targetName) = targetNameExpr.stringLiteral.tokenKind else {
            return .skipChildren
        }

        if targetName == "\"" + self.targetToFind + "\"" {
            self.foundTarget = node.parent as? FunctionCallArgumentListSyntax
            return .skipChildren
        }

        return .skipChildren
    }
}

// MARK: - Syntax Rewriters

/// Writer for "dependencies" array syntax.
final class DependenciesArrayWriter: SyntaxRewriter {

    override func visit(_ node: FunctionCallArgumentListSyntax) -> Syntax {
        let leadingTrivia = node.firstToken?.leadingTrivia ?? .zero

        let dependenciesArg = SyntaxFactory.makeFunctionCallArgument(
            label: SyntaxFactory.makeIdentifier("dependencies", leadingTrivia: leadingTrivia),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: SyntaxFactory.makeArrayExpr(
                leftSquare: SyntaxFactory.makeLeftSquareBracketToken(),
                elements: SyntaxFactory.makeBlankArrayElementList(),
                rightSquare: SyntaxFactory.makeRightSquareBracketToken()),
            trailingComma: SyntaxFactory.makeCommaToken()
        )

        // FIXME: This is not correct, we need to find the
        // proper position for inserting `dependencies: []`.
        return node.inserting(dependenciesArg, at: 1)
    }
}

/// Writer for inserting a trailing comma in an array expr.
final class ArrayTrailingCommaWriter: SyntaxRewriter {
    let lastElement: ArrayElementSyntax

    init(lastElement: ArrayElementSyntax) {
        self.lastElement = lastElement
    }

    override func visit(_ node: ArrayElementSyntax) -> Syntax {
        guard lastElement == node else {
            return node
        }
        return node.withTrailingComma(SyntaxFactory.makeCommaToken(trailingTrivia: .spaces(1)))
    }
}

/// Package dependency writer.
final class PackageDependencyWriter: SyntaxRewriter {

    /// The dependency url to write.
    let url: String

    /// The dependency requirement.
    let requirement: PackageDependencyRequirement

    init(url: String, requirement: PackageDependencyRequirement) {
        self.url = url
        self.requirement = requirement
    }

    override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {
        // FIXME: We should get the trivia from the closing brace.
        let leadingTrivia: Trivia = [.newlines(1), .spaces(8)]

        let dotPackageExpr = SyntaxFactory.makeMemberAccessExpr(
            base: nil,
            dot: SyntaxFactory.makePeriodToken(leadingTrivia: leadingTrivia),
            name: SyntaxFactory.makeIdentifier("package"),
            declNameArguments: nil
        )

        var args: [FunctionCallArgumentSyntax] = []

        let firstArgLabel = requirement == .localPackage ? "path" : "url"
        let url = SyntaxFactory.makeFunctionCallArgument(
            label: SyntaxFactory.makeIdentifier(firstArgLabel),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: SyntaxFactory.makeStringLiteralExpr(self.url),
            trailingComma: requirement == .localPackage ? nil : SyntaxFactory.makeCommaToken(trailingTrivia: .spaces(1))
        )
        args.append(url)

        // FIXME: Handle other types of requirements.
        if requirement != .localPackage {
            let secondArg = SyntaxFactory.makeFunctionCallArgument(
                label: SyntaxFactory.makeIdentifier("from"),
                colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
                expression: SyntaxFactory.makeStringLiteralExpr(requirement.ref!),
                trailingComma: nil
            )
            args.append(secondArg)
        }

        let expr = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: dotPackageExpr,
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeFunctionCallArgumentList(args),
            rightParen: SyntaxFactory.makeRightParenToken(),
            trailingClosure: nil
        )

        let newDependencyElement = SyntaxFactory.makeArrayElement(
            expression: expr,
            trailingComma: SyntaxFactory.makeCommaToken()
        )

        let rightBrace = SyntaxFactory.makeRightSquareBracketToken(
            leadingTrivia: [.newlines(1), .spaces(4)])

        return node.addArrayElement(newDependencyElement)
            .withRightSquare(rightBrace)
    }
}

/// Writer for inserting a target dependency.
final class TargetDependencyWriter: SyntaxRewriter {

    /// The name of the dependency to write.
    let dependencyName: String

    init(dependencyName name: String) {
        self.dependencyName = name
    }

    override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {
        var node = node

        // Insert trailing comma, if needed.
        if node.elements.count > 0 {
            let lastElement = node.elements.map{$0}.last!
            let trailingTriviaWriter = ArrayTrailingCommaWriter(lastElement: lastElement)
            let newElements = trailingTriviaWriter.visit(node.elements)
            node = node.withElements((newElements as! ArrayElementListSyntax))
        }

        let newDependencyElement = SyntaxFactory.makeArrayElement(
            expression: SyntaxFactory.makeStringLiteralExpr(self.dependencyName),
            trailingComma: nil
        )

        return node.addArrayElement(newDependencyElement)
    }
}

/// Writer for inserting a new target in a targets array.
final class NewTargetWriter: SyntaxRewriter {

    let name: String
    let targetType: TargetType

    init(name: String, targetType: TargetType) {
        self.name = name
        self.targetType = targetType
    }

    override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {

        let leadingTrivia: Trivia = [.newlines(1), .spaces(8)]
        let leadingTriviaArgs: Trivia = leadingTrivia.appending(.spaces(4))

        let dotPackageExpr = SyntaxFactory.makeMemberAccessExpr(
            base: nil,
            dot: SyntaxFactory.makePeriodToken(leadingTrivia: leadingTrivia),
            name: SyntaxFactory.makeIdentifier(targetType.factoryMethodName),
            declNameArguments: nil
        )

        let nameArg = SyntaxFactory.makeFunctionCallArgument(
            label: SyntaxFactory.makeIdentifier("name", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: SyntaxFactory.makeStringLiteralExpr(self.name),
            trailingComma: SyntaxFactory.makeCommaToken()
        )

        let emptyArray = SyntaxFactory.makeArrayExpr(leftSquare: SyntaxFactory.makeLeftSquareBracketToken(), elements: SyntaxFactory.makeBlankArrayElementList(), rightSquare: SyntaxFactory.makeRightSquareBracketToken())
        let depenenciesArg = SyntaxFactory.makeFunctionCallArgument(
            label: SyntaxFactory.makeIdentifier("dependencies", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: emptyArray,
            trailingComma: nil
        )

        let expr = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: dotPackageExpr,
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeFunctionCallArgumentList([
                nameArg, depenenciesArg,
                ]),
            rightParen: SyntaxFactory.makeRightParenToken(),
            trailingClosure: nil
        )

        let newDependencyElement = SyntaxFactory.makeArrayElement(
            expression: expr,
            trailingComma: SyntaxFactory.makeCommaToken()
        )

        return node.addArrayElement(newDependencyElement)
    }
}
