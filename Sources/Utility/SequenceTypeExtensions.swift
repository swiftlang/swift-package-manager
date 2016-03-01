/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension SequenceType {
    @warn_unused_result
    public func partition(@noescape include:(Generator.Element)->Bool) -> ([Generator.Element], [Generator.Element]) {
        var left = Array<Generator.Element>()
        var right = Array<Generator.Element>()
        
        for element in self {
            if include(element) {
                left.append(element)
            } else {
                right.append(element)
            }
        }
        
        return (left, right)
    }
}

