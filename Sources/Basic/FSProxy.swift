/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// FIXME: Eliminate this once we have a real Path type in Basic.
import Utility

public enum FSProxyError: ErrorProtocol {
    /// Access to the path is denied.
    ///
    /// Used in situations that correspond to the POSIX EACCES error code.
    case invalidAccess
    
    /// No such path exists.
    ///
    /// Used in situations that correspond to the POSIX ENOENT error code.
    case noEntry
    
    /// Not a directory
    ///
    /// Used in situations that correspond to the POSIX ENOTDIR error code.
    case notDirectory
}

/// Abstracted access to file system operations.
///
/// This protocol is used to allow most of the codebase to interact with a
/// natural filesystem interface, while still allowing clients to transparently
/// substitute a virtual file system or redirect file system operations.
///
/// NOTE: All of these APIs are synchronous and can block.
//
// FIXME: Design an asynchronous story?
public protocol FSProxy {
    /// Check whether the given path exists and is accessible.
    func exists(_ path: String) -> Bool
    
    /// Check whether the given path is accessible and a directory.
    func isDirectory(_ path: String) -> Bool
    
    /// Get the contents of the given directory, in an undefined order.
    //
    // FIXME: Actual file system interfaces will allow more efficient access to
    // more data than just the name here.
    func getDirectoryContents(_ path: String) throws -> [String]
}

/// Concrete FSProxy implementation which communicates with the local file system.
class LocalFS: FSProxy {
    func exists(_ path: String) -> Bool {
        fatalError()
    }
    
    func isDirectory(_ path: String) -> Bool {
        fatalError()
    }
    
    func getDirectoryContents(_ path: String) throws -> [String] {
        fatalError()
    }
}

/// Concrete FSProxy implementation which simulates an empty disk.
//
// FIXME: This class does not yet support concurrent mutation safely.
public class PseudoFS: FSProxy {
    private class Node {
        /// The actual node data.
        let contents: NodeContents
        
        init(_ contents: NodeContents) {
            self.contents = contents
        }
    }
    private enum NodeContents {
        case File(ByteString)
        case Directory(DirectoryContents)
    }    
    private class DirectoryContents {
        var entries:  [String: Node]

        init(entries: [String: Node] = [:]) {
            self.entries = entries
        }
    }
    
    /// The root filesytem.
    private var root: Node

    public init() {
        root = Node(.Directory(DirectoryContents()))
    }

    /// Get the node corresponding to get given path.
    private func getNode(_ path: String) throws -> Node? {
        func getNodeInternal(_ path: String) throws -> Node? {
            // If this is the root node, return it.
            if path == "/" {
                return root
            }

            // Otherwise, get the parent node.
            guard let parent = try getNodeInternal(path.parentDirectory) else {
                return nil
            }

            // If we didn't find a directory, this is an error.
            //
            // FIXME: Error handling.
            guard case .Directory(let contents) = parent.contents else {
                throw FSProxyError.notDirectory
            }

            // Return the directory entry.
            return contents.entries[path.basename]
        }

        // Get the node using the normalized path.
        precondition(path.isAbsolute, "input path must be absolute")
        return try getNodeInternal(path.normpath)
    }

    // MARK: FSProxy Implementation
    
    public func exists(_ path: String) -> Bool {
        do {
            return try getNode(path) != nil
        } catch {
            return false
        }
    }
    
    public func isDirectory(_ path: String) -> Bool {
        do {
            if case .Directory? = try getNode(path)?.contents {
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    public func getDirectoryContents(_ path: String) throws -> [String] {
        guard let node = try getNode(path) else {
            throw FSProxyError.noEntry
        }
        guard case .Directory(let contents) = node.contents else {
            throw FSProxyError.notDirectory
        }

        // FIXME: Perhaps we should change the protocol to allow lazy behavior.
        return [String](contents.entries.keys)
    }
}
