/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@_exported import OrderedCollections
@_exported import TSCBasic
// override TSC versions until deprecated
// TODO: remove once TSC removes these
public typealias OrderedSet = OrderedCollections.OrderedSet
public typealias OrderedDictionary = OrderedCollections.OrderedDictionary
