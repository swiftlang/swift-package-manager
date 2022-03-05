/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utils

public struct Game: Equatable {
    public var levels: [LevelDetector]

    public static func startGame(for user: String) -> Int {
        if user.isEmpty {
            return -1
        }
        return LevelDetector.detect(for: user)
    }
}
