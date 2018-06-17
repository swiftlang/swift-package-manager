/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import clibc
import Basic
import Foundation

/// The branch object.
public final class Branch: Reference {
    public enum Kind {
        case local
        case remote
        case all

        var git_branch_t: git_branch_t {
            switch self {
            case .local:
                return GIT_BRANCH_LOCAL
            case .remote:
                return GIT_BRANCH_REMOTE
            case .all:
                return GIT_BRANCH_ALL
            }
        }
    }

    /// The branch name.
    public lazy var name: String = {
        return try! lock.withLock {
            var name: UnsafePointer<Int8>?
            try validate(git_branch_name(&name, handle))
            return String(cString: name!)
        }
    }()
}
