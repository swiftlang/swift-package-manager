/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel

protocol Buildable {
    var targetName: String { get }
    var isTest: Bool { get }
}

extension Module: Buildable {
    var targetName: String {
        return "<\(name).module>"
    }
}

extension Product: Buildable {
    var isTest: Bool {
        if case .test = type {
            return true
        }
        return false
    }

    var targetName: String {
        switch type {
        case .library(.dynamic):
            return "<\(name).dylib>"
        case .test:
            return "<\(name).test>"
        case .library(.static):
            return "<\(name).a>"
        case .library(.none):
            fatalError("unexpected call")
        case .executable:
            return "<\(name).exe>"
        }
    }
}
