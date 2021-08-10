/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */


/// Provides information about a list of files. The order is not defined
/// but is guaranteed to be stable. This allows the implementation to be
/// more efficient than a static file list.
public struct FileList: Decodable {
    private var files: [FileInfo]
}
extension FileList: Sequence {
    public struct Iterator: IteratorProtocol {
        private var files: ArraySlice<FileInfo>
        fileprivate init(files: ArraySlice<FileInfo>) {
            self.files = files
        }
        mutating public func next() -> FileInfo? {
            guard let nextInfo = self.files.popFirst() else {
                return nil
            }
            return nextInfo
        }
    }
    public func makeIterator() -> Iterator {
        return Iterator(files: ArraySlice(self.files))
    }
}

/// Provides information about a single file in a FileList.
public struct FileInfo: Decodable {
    /// The path of the file.
    public let path: Path
    /// File type, as determined by SwiftPM.
    public let type: FileType
}

/// Provides information about a the type of a file. Any future cases will
/// use availability annotations to make sure existing plugins still work
/// until they increase their required tools version.
public enum FileType: String, Decodable {
    /// A source file.
    case source
    /// A resource file (either processed or copied).
    case resource
    /// A file not covered by any other rule.
    case unknown
}
