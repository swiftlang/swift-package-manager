/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic


public enum GitProgress {
    case enumeratingObjects(currentObjects: Int)
    case countingObjects(progress: Double, currentObjects: Int, totalObjects: Int)
    case compressingObjects(progress: Double, currentObjects: Int, totalObjects: Int)
    case receivingObjects(progress: Double, currentObjects: Int, totalObjects: Int, downloadProgress: String?, downloadSpeed: String?)
    case resolvingDeltas(progress: Double, currentObjects: Int, totalObjects: Int)

    public typealias Handler = (GitProgress) -> Void

    /// The pattern used to match git output. Caputre groups are labled from ?<i0> to ?<i19>.
    static let pattern = #"""
(?xi)
(?:
    remote: \h+ (?<i0>Enumerating \h objects): \h+ (?<i1>[0-9]+)
)|
(?:
    remote: \h+ (?<i2>Counting \h objects): \h+ (?<i3>[0-9]+)% \h+ \((?<i4>[0-9]+)\/(?<i5>[0-9]+)\)
)|
(?:
    remote: \h+ (?<i6>Compressing \h objects): \h+ (?<i7>[0-9]+)% \h+ \((?<i8>[0-9]+)\/(?<i9>[0-9]+)\)
)|
(?:
    (?<i10>Resolving \h deltas): \h+ (?<i11>[0-9]+)% \h+ \((?<i12>[0-9]+)\/(?<i13>[0-9]+)\)
)|
(?:
    (?<i14>Receiving \h objects): \h+ (?<i15>[0-9]+)% \h+ \((?<i16>[0-9]+)\/(?<i17>[0-9]+)\)
    (?:, \h+ (?<i18>[0-9]+.?[0-9]+ \h [A-Z]iB) \h+ \| \h+ (?<i19>[0-9]+.?[0-9]+ \h [A-Z]iB\/s))?
)
"""#
    static let regex = try? RegEx(pattern: pattern)

    init?(from string: String) {
        guard let matches = GitProgress.regex?.matchGroups(in: string).first, matches.count == 20 else { return nil }

        if matches[0] == "Enumerating objects" {
            guard let currentObjects = Int(matches[1]) else { return nil }

            self = .enumeratingObjects(currentObjects: currentObjects)
        } else if matches[2] == "Counting objects" {
            guard let progress = Double(matches[3]),
                  let currentObjects = Int(matches[4]),
                  let totalObjects = Int(matches[5]) else { return nil }

            self = .countingObjects(progress: progress / 100, currentObjects: currentObjects, totalObjects: totalObjects)

        } else if matches[6] == "Compressing objects" {
            guard let progress = Double(matches[7]),
                  let currentObjects = Int(matches[8]),
                  let totalObjects = Int(matches[9]) else { return nil }

            self = .compressingObjects(progress: progress / 100, currentObjects: currentObjects, totalObjects: totalObjects)

        } else if matches[10] == "Resolving deltas" {
            guard let progress = Double(matches[11]),
                  let currentObjects = Int(matches[12]),
                  let totalObjects = Int(matches[13]) else { return nil }

            self = .resolvingDeltas(progress: progress / 100, currentObjects: currentObjects, totalObjects: totalObjects)

        } else if matches[14] == "Receiving objects" {
            guard let progress = Double(matches[15]),
                  let currentObjects = Int(matches[16]),
                  let totalObjects = Int(matches[17]) else { return nil }

            let downloadProgress = matches[18]
            let downloadSpeed = matches[19]

            self = .receivingObjects(progress: progress / 100, currentObjects: currentObjects, totalObjects: totalObjects, downloadProgress: downloadProgress, downloadSpeed: downloadSpeed)

        } else {
            return nil
        }
    }

    public var message: String {
        switch self {
        case .enumeratingObjects: return "Enumerating objects"
        case .countingObjects: return "Counting objects"
        case .compressingObjects: return "Compressing objects"
        case .receivingObjects: return "Receiving objects"
        case .resolvingDeltas: return "Resolving deltas"
        }
    }

    /// Processes stdout output and calls the progress callback with `GitStatus` objects.
    static func gitStatusFilter(_ bytes: [UInt8], progress: GitProgress.Handler) {
        guard let string = String(bytes: bytes, encoding: .utf8) else { return }
        let lines = string
            .split { $0 == "\r" || $0 == "\n"  }
            .map { String($0) }

        for line in lines {
            if let status = GitProgress(from: line) {
                progress(status)
            }
        }
    }
}
