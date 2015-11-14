/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: ErrorType {
    case InvalidModuleName(String)
    case InvalidManifest(String, errors: [String], data: String)
    case ManifestTargetNotFound(String)
    case InvalidDependencyGraph(String)
    case InvalidSourcesLayout([String])
    case UpdateRequired(String)
}
