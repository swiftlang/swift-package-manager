/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SwiftSyntax
import TSCBasic
import TSCUtility
import PackageModel

/// A package manifest rewriter.
///
/// This class provides functionality for rewriting the
/// Swift package manifest using the SwiftSyntax library.
///
/// Similar to SwiftSyntax, this class only deals with the
/// syntax and has no functionality for semantics of the manifest.
public final class ManifestRewriter {

    /// The contents of the original manifest.
    public let originalManifest: String

    /// The contents of the edited manifest.
    public var editedManifest: String {
        return editedSource.description
    }

    /// The edited manifest syntax.
    private var editedSource: SourceFileSyntax

    /// Create a new manfiest editor with the given contents.
    public init(_ manifest: String) throws {
        self.originalManifest = manifest
        self.editedSource = try SyntaxParser.parse(source: manifest)
    }

    /// Add a package dependency.
    public func addPackageDependency(
        name: String,
        url: String,
        requirement: PackageDependencyRequirement
    ) throws {
        let initFnExpr = try findPackageInit()

        // Find dependencies section in the argument list of Package(...).
        let packageDependenciesFinder = ArrayExprArgumentFinder(expectedLabel: "dependencies")
        packageDependenciesFinder.walk(initFnExpr.argumentList)

        let packageDependencies: ArrayExprSyntax
        if let existingPackageDependencies = packageDependenciesFinder.foundArrayExpr {
            packageDependencies = existingPackageDependencies
        } else {
            // We didn't find a dependencies section so insert one.
            let argListWithDependencies = EmptyArrayArgumentWriter(argumentLabel: "dependencies",
                                                                   followingArgumentLabels:
                                                                   "targets",
                                                                   "swiftLanguageVersions",
                                                                   "cLanguageStandard",
                                                                   "cxxLanguageStandard")
                .visit(initFnExpr.argumentList)

            // Find the inserted section.
            let packageDependenciesFinder = ArrayExprArgumentFinder(expectedLabel: "dependencies")
            packageDependenciesFinder.walk(argListWithDependencies)
            packageDependencies = packageDependenciesFinder.foundArrayExpr!
        }

        // Add the the package dependency entry.
       let newManifest = PackageDependencyWriter(
            name: name,
            url: url,
            requirement: requirement,
            sourceFileSyntax: editedSource
        ).visit(packageDependencies).root

        self.editedSource = newManifest.as(SourceFileSyntax.self)!
    }

    /// Add a target dependency.
    public func addTargetDependency(
        target: String,
        dependency: String
    ) throws {
        let initFnExpr = try findPackageInit()

        // Find the `targets: []` array.
        let targetsArrayFinder = ArrayExprArgumentFinder(expectedLabel: "targets")
        targetsArrayFinder.walk(initFnExpr.argumentList)
        guard let targetsArrayExpr = targetsArrayFinder.foundArrayExpr else {
            throw StringError("Couldn't find 'targets' argument")
        }

        // Find the target node.
        let targetFinder = NamedEntityArgumentListFinder(name: target)
        targetFinder.walk(targetsArrayExpr)
        guard let targetNode = targetFinder.foundEntity else {
            throw StringError("couldn't find target '\(target)'")
        }

        let targetDependencyFinder = ArrayExprArgumentFinder(expectedLabel: "dependencies")
        targetDependencyFinder.walk(targetNode)

        guard let targetDependencies = targetDependencyFinder.foundArrayExpr else {
            throw StringError("couldn't find 'dependencies' argument")
        }

        // Add the target dependency entry.
        let newManifest = targetDependencies.withAdditionalElementExpr(ExprSyntax(
            SyntaxFactory.makeStringLiteralExpr(dependency)
        )).root

        self.editedSource = newManifest.as(SourceFileSyntax.self)!
    }

    /// Add a new target.
    public func addTarget(
        targetName: String,
        factoryMethodName: String
    ) throws {
        let initFnExpr = try findPackageInit()
        let targetsNode = findOrCreateTargetsList(in: initFnExpr)

        //FIXME: determine from source
        let leadingTrivia: Trivia = [.newlines(1), .spaces(8)]
        let leadingTriviaArgs: Trivia = leadingTrivia.appending(.spaces(4))

        let dotTargetExpr = SyntaxFactory.makeMemberAccessExpr(
            base: nil,
            dot: SyntaxFactory.makePeriodToken(leadingTrivia: leadingTrivia),
            name: SyntaxFactory.makeIdentifier(factoryMethodName),
            declNameArguments: nil
        )

        let nameArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("name", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(targetName)),
            trailingComma: SyntaxFactory.makeCommaToken()
        )

        let emptyArray = SyntaxFactory.makeArrayExpr(leftSquare: SyntaxFactory.makeLeftSquareBracketToken(), elements: SyntaxFactory.makeBlankArrayElementList(), rightSquare: SyntaxFactory.makeRightSquareBracketToken())
        let depenenciesArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("dependencies", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(emptyArray),
            trailingComma: nil
        )

        let expr = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: ExprSyntax(dotTargetExpr),
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeTupleExprElementList([
                nameArg, depenenciesArg,
            ]),
            rightParen: SyntaxFactory.makeRightParenToken(),
            trailingClosure: nil,
            additionalTrailingClosures: nil
        )

        let newManifest = targetsNode.withAdditionalElementExpr(ExprSyntax(expr)).root

        self.editedSource = newManifest.as(SourceFileSyntax.self)!
    }

    public func addBinaryTarget(targetName: String,
                                urlOrPath: String,
                                checksum: String?) throws {
        let initFnExpr = try findPackageInit()
        let targetsNode = findOrCreateTargetsList(in: initFnExpr)

        //FIXME: determine from source
        let leadingTrivia: Trivia = [.newlines(1), .spaces(8)]
        let leadingTriviaArgs: Trivia = leadingTrivia.appending(.spaces(4))

        let dotTargetExpr = SyntaxFactory.makeMemberAccessExpr(
            base: nil,
            dot: SyntaxFactory.makePeriodToken(leadingTrivia: leadingTrivia),
            name: SyntaxFactory.makeIdentifier("binaryTarget"),
            declNameArguments: nil
        )

        var args: [TupleExprElementSyntax] = []

        let nameArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("name", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(targetName)),
            trailingComma: SyntaxFactory.makeCommaToken()
        )
        args.append(nameArg)

        if TSCUtility.URL.scheme(urlOrPath) == nil {
            guard checksum == nil else {
                throw StringError("'\(urlOrPath)' is a local path, but a checksum was specified")
            }

            let pathArg = SyntaxFactory.makeTupleExprElement(
                label: SyntaxFactory.makeIdentifier("path", leadingTrivia: leadingTriviaArgs),
                colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
                expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(urlOrPath)),
                trailingComma: nil
            )
            args.append(pathArg)
        } else {
            guard let checksum = checksum else {
                throw StringError("'\(urlOrPath)' is not a local path, but no checksum was specified")
            }

            let urlArg = SyntaxFactory.makeTupleExprElement(
                label: SyntaxFactory.makeIdentifier("url", leadingTrivia: leadingTriviaArgs),
                colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
                expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(urlOrPath)),
                trailingComma: SyntaxFactory.makeCommaToken()
            )
            args.append(urlArg)

            let checksumArg = SyntaxFactory.makeTupleExprElement(
                label: SyntaxFactory.makeIdentifier("checksum", leadingTrivia: leadingTriviaArgs),
                colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
                expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(checksum)),
                trailingComma: nil
            )
            args.append(checksumArg)
        }

        let expr = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: ExprSyntax(dotTargetExpr),
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeTupleExprElementList(args),
            rightParen: SyntaxFactory.makeRightParenToken(),
          trailingClosure: nil,
          additionalTrailingClosures: nil
        )

        let newManifest = targetsNode.withAdditionalElementExpr(ExprSyntax(expr)).root

        self.editedSource = newManifest.as(SourceFileSyntax.self)!
    }

    // Add a new product.
    public func addProduct(name: String, type: ProductType) throws {
        let initFnExpr = try findPackageInit()

        let productsFinder = ArrayExprArgumentFinder(expectedLabel: "products")
        productsFinder.walk(initFnExpr.argumentList)
        let productsNode: ArrayExprSyntax

        if let existingProducts = productsFinder.foundArrayExpr {
            productsNode = existingProducts
        } else {
            // We didn't find a products section, so insert one.
            let argListWithProducts = EmptyArrayArgumentWriter(argumentLabel: "products",
                                                               followingArgumentLabels:
                                                               "dependencies",
                                                               "targets",
                                                               "swiftLanguageVersions",
                                                               "cLanguageStandard",
                                                               "cxxLanguageStandard")
                .visit(initFnExpr.argumentList)

            // Find the inserted section.
            let productsFinder = ArrayExprArgumentFinder(expectedLabel: "products")
            productsFinder.walk(argListWithProducts)
            productsNode = productsFinder.foundArrayExpr!
        }

        let newManifest = NewProductWriter(
            name: name, type: type
        ).visit(productsNode).root

        self.editedSource = newManifest.as(SourceFileSyntax.self)!
    }

    // Add a target to a product.
    public func addProductTarget(product: String, target: String) throws {
        let initFnExpr = try findPackageInit()

        // Find the `products: []` array.
        let productsArrayFinder = ArrayExprArgumentFinder(expectedLabel: "products")
        productsArrayFinder.walk(initFnExpr.argumentList)
        guard let productsArrayExpr = productsArrayFinder.foundArrayExpr else {
            throw StringError("Couldn't find 'products' argument")
        }

        // Find the product node.
        let productFinder = NamedEntityArgumentListFinder(name: product)
        productFinder.walk(productsArrayExpr)
        guard let productNode = productFinder.foundEntity else {
            throw StringError("couldn't find product '\(product)'")
        }

        let productTargetsFinder = ArrayExprArgumentFinder(expectedLabel: "targets")
        productTargetsFinder.walk(productNode)

        guard let productTargets = productTargetsFinder.foundArrayExpr else {
            throw StringError("couldn't find 'targets' argument")
        }

        let newManifest = productTargets.withAdditionalElementExpr(ExprSyntax(
            SyntaxFactory.makeStringLiteralExpr(target)
        )).root

        self.editedSource = newManifest.as(SourceFileSyntax.self)!
    }

    private func findOrCreateTargetsList(in packageInitExpr: FunctionCallExprSyntax) -> ArrayExprSyntax {
        let targetsFinder = ArrayExprArgumentFinder(expectedLabel: "targets")
        targetsFinder.walk(packageInitExpr.argumentList)

        let targetsNode: ArrayExprSyntax
        if let existingTargets = targetsFinder.foundArrayExpr {
            targetsNode = existingTargets
        } else {
            // We didn't find a targets section, so insert one.
            let argListWithTargets = EmptyArrayArgumentWriter(argumentLabel: "targets",
                                                              followingArgumentLabels:
                                                              "swiftLanguageVersions",
                                                              "cLanguageStandard",
                                                              "cxxLanguageStandard")
                .visit(packageInitExpr.argumentList)

            // Find the inserted section.
            let targetsFinder = ArrayExprArgumentFinder(expectedLabel: "targets")
            targetsFinder.walk(argListWithTargets)
            targetsNode = targetsFinder.foundArrayExpr!
        }

        return targetsNode
    }

    private func findPackageInit() throws -> FunctionCallExprSyntax {
        // Find Package initializer.
        let packageFinder = PackageInitFinder()
        packageFinder.walk(editedSource)
        guard let initFnExpr = packageFinder.packageInit else {
            throw StringError("couldn't find 'Package' initializer")
        }
        return initFnExpr
    }
}

// MARK: - Syntax Visitors

/// Package init finder.
final class PackageInitFinder: SyntaxVisitor {

    /// Reference to the function call of the package initializer.
    private(set) var packageInit: FunctionCallExprSyntax?

    override func visit(_ node: InitializerClauseSyntax) -> SyntaxVisitorContinueKind {
        if let fnCall = FunctionCallExprSyntax(Syntax(node.value)),
            let identifier = fnCall.calledExpression.firstToken,
            identifier.text == "Package" {
            assert(packageInit == nil, "Found two package initializers")
            packageInit = fnCall
        }
        return .skipChildren
    }
}

/// Finder for an array expression used as or as part of a labeled argument.
final class ArrayExprArgumentFinder: SyntaxVisitor {

    private(set) var foundArrayExpr: ArrayExprSyntax?
    private let expectedLabel: String

    init(expectedLabel: String) {
        self.expectedLabel = expectedLabel
        super.init()
    }

    override func visit(_ node: TupleExprElementSyntax) -> SyntaxVisitorContinueKind {
        guard node.label?.text == expectedLabel else {
            return .skipChildren
        }

        // We have custom code like foo + bar + [] (hopefully there is an array expr here).
        if let seq = node.expression.as(SequenceExprSyntax.self) {
            foundArrayExpr = seq.elements.first(where: { $0.is(ArrayExprSyntax.self) })?.as(ArrayExprSyntax.self)
        } else if let arrayExpr = node.expression.as(ArrayExprSyntax.self) {
            foundArrayExpr = arrayExpr
        }

        // FIXME: If we find a dependencies section but not an array expr, then we should
        // not try to insert one later. i.e. return error if depsArray is nil.

        return .skipChildren
    }
}

/// Given an Array expression of call expressions, find the argument list of the call
/// expression with the specified `name` argument.
final class NamedEntityArgumentListFinder: SyntaxVisitor {

    let entityToFind: String
    private(set) var foundEntity: TupleExprElementListSyntax?

    init(name: String) {
        self.entityToFind = name
    }

    override func visit(_ node: TupleExprElementSyntax) -> SyntaxVisitorContinueKind {
        guard case .identifier(let label)? = node.label?.tokenKind else {
            return .skipChildren
        }
        guard label == "name", let targetNameExpr = node.expression.as(StringLiteralExprSyntax.self),
              targetNameExpr.segments.count == 1, let segment = targetNameExpr.segments.first?.as(StringSegmentSyntax.self) else {
            return .skipChildren
        }

        guard case .stringSegment(let name) = segment.content.tokenKind else {
            return .skipChildren
        }

        if name == self.entityToFind {
            self.foundEntity = node.parent?.as(TupleExprElementListSyntax.self)
            return .skipChildren
        }

        return .skipChildren
    }
}

// MARK: - Syntax Rewriters

/// Writer for an empty array argument.
final class EmptyArrayArgumentWriter: SyntaxRewriter {
    let argumentLabel: String
    let followingArgumentLabels: Set<String>

    init(argumentLabel: String, followingArgumentLabels: String...) {
        self.argumentLabel = argumentLabel
        self.followingArgumentLabels = .init(followingArgumentLabels)
    }

    override func visit(_ node: TupleExprElementListSyntax) -> Syntax {
        let leadingTrivia = node.firstToken?.leadingTrivia ?? .zero

        let existingLabels = node.map(\.label?.text)
        let insertionIndex = existingLabels.firstIndex {
            followingArgumentLabels.contains($0 ?? "")
        } ?? existingLabels.endIndex

        let dependenciesArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier(argumentLabel, leadingTrivia: leadingTrivia),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeArrayExpr(
                                    leftSquare: SyntaxFactory.makeLeftSquareBracketToken(),
                                    elements: SyntaxFactory.makeBlankArrayElementList(),
                                    rightSquare: SyntaxFactory.makeRightSquareBracketToken())),
            trailingComma: insertionIndex != existingLabels.endIndex ? SyntaxFactory.makeCommaToken() : nil
        )

        var newNode = node
        if let lastArgument = newNode.last,
           insertionIndex == existingLabels.endIndex {
            // If the new argument is being added at the end of the list, the argument before it needs a comma.
            newNode = newNode.replacing(childAt: newNode.count-1,
                                        with: lastArgument.withTrailingComma(SyntaxFactory.makeCommaToken()))
        }
        
        return Syntax(newNode.inserting(dependenciesArg, at: insertionIndex))
    }
}

/// Package dependency writer.
final class PackageDependencyWriter: SyntaxRewriter {

    /// The dependency name to write.
    let name: String

    /// The dependency url to write.
    let url: String

    /// The dependency requirement.
    let requirement: PackageDependencyRequirement

    /// The syntax node representing the containing source file.
    let sourceFileSyntax: SourceFileSyntax

    init(name: String,
         url: String,
         requirement: PackageDependencyRequirement,
         sourceFileSyntax: SourceFileSyntax) {
        self.name = name
        self.url = url
        self.requirement = requirement
        self.sourceFileSyntax = sourceFileSyntax
    }

    override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {

        let dotPackageExpr = SyntaxFactory.makeMemberAccessExpr(
            base: nil,
            dot: SyntaxFactory.makePeriodToken(),
            name: SyntaxFactory.makeIdentifier("package"),
            declNameArguments: nil
        )

        var args: [TupleExprElementSyntax] = []

        let nameArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("name"),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(self.name)),
            trailingComma: SyntaxFactory.makeCommaToken(trailingTrivia: .spaces(1))
        )
        args.append(nameArg)

        let locationArgLabel = requirement == .localPackage ? "path" : "url"
        let locationArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier(locationArgLabel),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(self.url)),
            trailingComma: requirement == .localPackage ? nil : SyntaxFactory.makeCommaToken(trailingTrivia: .spaces(1))
        )
        args.append(locationArg)

        let addArg = { (baseName: String, argumentLabel: String?, argumentString: String) in
            let memberExpr = SyntaxFactory.makeMemberAccessExpr(base: nil,
                                                                dot: SyntaxFactory.makePeriodToken(),
                                                                name: SyntaxFactory.makeIdentifier(baseName),
                                                                declNameArguments: nil)
            let argList = SyntaxFactory.makeTupleExprElementList([
                SyntaxFactory.makeTupleExprElement(label: argumentLabel.map { SyntaxFactory.makeIdentifier($0) },
                                                   colon: argumentLabel.map { _ in SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)) },
                                                   expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(argumentString)),
                                                   trailingComma: nil)
            ])
            let exactExpr = SyntaxFactory.makeFunctionCallExpr(calledExpression: ExprSyntax(memberExpr),
                                                               leftParen: SyntaxFactory.makeLeftParenToken(),
                                                               argumentList: argList,
                                                               rightParen: SyntaxFactory.makeRightParenToken(),
                                                               trailingClosure: nil,
                                                               additionalTrailingClosures: nil)
            let exactArg = SyntaxFactory.makeTupleExprElement(label: nil,
                                                              colon: nil,
                                                              expression: ExprSyntax(exactExpr),
                                                              trailingComma: nil)
            args.append(exactArg)
        }

        switch requirement {
        case .exact(let version):
            addArg("exact", nil, version)
        case .revision(let revision):
            addArg("revision", nil, revision)
        case .branch(let branch):
            addArg("branch", nil, branch)
        case .upToNextMajor(let version):
            addArg("upToNextMajor", "from", version)
        case .upToNextMinor(let version):
            addArg("upToNextMinor", "from", version)
        case .localPackage:
            break
        }

        let expr = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: ExprSyntax(dotPackageExpr),
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeTupleExprElementList(args),
            rightParen: SyntaxFactory.makeRightParenToken(),
          trailingClosure: nil,
          additionalTrailingClosures: nil
        )

        return ExprSyntax(node.withAdditionalElementExpr(ExprSyntax(expr)))
    }
}

/// Writer for inserting a new product in a products array.
final class NewProductWriter: SyntaxRewriter {

    let name: String
    let type: ProductType

    init(name: String, type: ProductType) {
        self.name = name
        self.type = type
    }

    override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {

        // FIXME: determine from source
        let leadingTrivia: Trivia = [.newlines(1), .spaces(8)]
        let leadingTriviaArgs: Trivia = leadingTrivia.appending(.spaces(4))

        let dotExpr = SyntaxFactory.makeMemberAccessExpr(
            base: nil,
            dot: SyntaxFactory.makePeriodToken(leadingTrivia: leadingTrivia),
            name: SyntaxFactory.makeIdentifier(type == .executable ? "executable" : "library"),
            declNameArguments: nil
        )

        var args: [TupleExprElementSyntax] = []

        let nameArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("name", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeStringLiteralExpr(name)),
            trailingComma: SyntaxFactory.makeCommaToken()
        )
        args.append(nameArg)

        if case .library(let kind) = type, kind != .automatic {
            let typeExpr = SyntaxFactory.makeMemberAccessExpr(base: nil,
                                                              dot: SyntaxFactory.makePeriodToken(),
                                                              name: SyntaxFactory.makeIdentifier(kind == .dynamic ? "dynamic" : "static"),
                                                              declNameArguments: nil)
            let typeArg = SyntaxFactory.makeTupleExprElement(
                label: SyntaxFactory.makeIdentifier("type", leadingTrivia: leadingTriviaArgs),
                colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
                expression: ExprSyntax(typeExpr),
                trailingComma: SyntaxFactory.makeCommaToken()
            )
            args.append(typeArg)
        }

        let emptyArray = SyntaxFactory.makeArrayExpr(leftSquare: SyntaxFactory.makeLeftSquareBracketToken(),
                                                     elements: SyntaxFactory.makeBlankArrayElementList(),
                                                     rightSquare: SyntaxFactory.makeRightSquareBracketToken())
        let targetsArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("targets", leadingTrivia: leadingTriviaArgs),
            colon: SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)),
            expression: ExprSyntax(emptyArray),
            trailingComma: nil
        )
        args.append(targetsArg)

        let expr = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: ExprSyntax(dotExpr),
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeTupleExprElementList(args),
            rightParen: SyntaxFactory.makeRightParenToken(),
          trailingClosure: nil,
          additionalTrailingClosures: nil
        )

        return ExprSyntax(node.withAdditionalElementExpr(ExprSyntax(expr)))
    }
}
