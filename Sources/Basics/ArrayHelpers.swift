//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public func nextItem<T: Equatable>(in array: [T], after item: T) -> T? {
    for (index, element) in array.enumerated() {
        if element == item {
            let nextIndex = index + 1
            return nextIndex < array.count ? array[nextIndex] : nil
        }
    }
    return nil // Item not found or it's the last item
}
