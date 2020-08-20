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
    let master: Int32
    let slave: Int32
    public var outStream: LocalFileOutputByteStream
    
    public init?(){
        var master: Int32 = 0
        var slave: Int32 = 0
        if openpty(&master, &slave, nil, nil, nil) != 0 {
            return nil
        }
        guard let outStream = try? LocalFileOutputByteStream(filePointer: fdopen(slave, "w"), closeOnDeinit: false) else {
            return nil
        }
        self.outStream = outStream
        self.master = master
        self.slave = slave
    }
    
    public func readMaster(maxChars n: Int = 1000) -> String? {
        var buf: [CChar] = [CChar](repeating: 0, count: n)
        if read(master, &buf, n) <= 0 {
            return nil
        }
        return String(cString: buf)
    }
    
    public func closeSlave() {
        _ = TSCLibc.close(slave)
    }
    
    public func closeMaster() {
        _ = TSCLibc.close(master)
    }
    
    public func close() {
        closeSlave()
        closeMaster()
    }
}
#endif
