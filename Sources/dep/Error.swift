/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public typealias PathString = String

public enum Error: ErrorType {
    case NotASandbox(PathString)
    case NotEmpty(PathString)
    case CorruptSandbox(PathString)
    case AlreadySandbox(PathString)
    case CouldNotAccessSandbox(PathString)
    case CannotCheckout(String, PathString)
    case CannotInstall(String, PathString)
    case Versionless(String)
    case InvalidModuleName(String)
    case TargetEmpty(PathString)
    case UnknownModule(String)
    case UnversionedDependency(Package, String)
    case InvalidManifest(String, errors: [String], data: String)
    case ManifestTargetNotFound(String)

    case InvalidDependencyGraph(String)
    case InvalidSourcesLayout([String])

    case UpdateRequired(String)
}
