/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCLibc

#if os(Windows)
#else
public final class PseudoTerminal {
    let primary: Int32
    let secondary: Int32
    public var outStream: LocalFileOutputByteStream
    
    public init?(){
        var primary: Int32 = 0
        var secondary: Int32 = 0
        if openpty(&primary, &secondary, nil, nil, nil) != 0 {
            return nil
        }
        guard let outStream = try? LocalFileOutputByteStream(filePointer: fdopen(secondary, "w"), closeOnDeinit: false) else {
            return nil
        }
        self.outStream = outStream
        self.primary = primary
        self.secondary = secondary
    }
    
    public func readPrimary(maxChars n: Int = 1000) -> String? {
        var buf: [CChar] = [CChar](repeating: 0, count: n)
        if read(primary, &buf, n) <= 0 {
            return nil
        }
        return String(cString: buf)
    }
    
    public func closeSecondary() {
        _ = TSCLibc.close(secondary)
    }
    
    public func closePrimary() {
        _ = TSCLibc.close(primary)
    }
    
    public func close() {
        closeSecondary()
        closePrimary()
    }
}
#endif
