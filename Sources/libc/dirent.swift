/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file defines a common type alias for the result of opendir().
*/

#if os(Linux)
public typealias DirHandle = OpaquePointer
#else
public typealias DirHandle = UnsafeMutablePointer<DIR>
#endif
