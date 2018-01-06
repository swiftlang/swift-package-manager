/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Computes the number of edits needed to transform first string to second.
public func editDistance(_ first: String, _ second: String) -> Int {
    let a = Array(first.utf16)
    let b = Array(second.utf16)
    var distance = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count {
        for j in 0...b.count {
            if i == 0 {
                distance[i][j] = j
            } else if j == 0 {
                distance[i][j] = i
            } else if a[i - 1] == b[j - 1] {
                distance[i][j] = distance[i - 1][j - 1]
            } else {
                let insertion = distance[i][ j - 1]
                let deletion = distance[i - 1][j]
                let replacement = distance[i - 1][j - 1]
                distance[i][j] = 1 + min(insertion, deletion, replacement)
            }
        }
    }
    return distance[a.count][b.count]
}
