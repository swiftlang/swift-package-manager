/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

protocol Fetchable {
    var currentVersion: Version { get }
    var children: [(String, Range<Version>)] { get }

    /**
     This should be a separate protocol. But Swift 2 was not happy
     with the result since `U: T` this upset the type system when
     we needed to collect U as T. FIXME
     */
    var availableVersions: [Version] { get }

    func constrain(to versionRange: Range<Version>) -> Version?

    //FIXME protocols cannot impose new property constraints,
    // so Package has a version { get } already, we cannot add
    // a set, so instead we have to have this protocol func
    func setCurrentVersion(_ newValue: Version) throws
}
