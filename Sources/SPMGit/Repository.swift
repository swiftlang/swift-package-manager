/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import clibc
import Basic
import Foundation

final public class Repository {
    typealias Handle = OpaquePointer

    /// libgit handle.
    private let handle: Handle

    /// Path to the repository.
    public let path: AbsolutePath

    /// Clone operation.
    @discardableResult
    public static func clone(from url: String, to path: AbsolutePath) throws -> Repository? {
        try initializeGit()

        var options = git_clone_options()
        try validate(git_clone_init_options(&options, UInt32(GIT_CLONE_OPTIONS_VERSION)))

        var handle: Handle?
        try validate(git_clone(&handle, url, path.asString, &options))
        return Repository(handle: handle!, path: path)
    }

    private init(handle: Handle, path: AbsolutePath) {
        self.handle = handle
        self.path = path
    }

    /// Open a local repository.
    public convenience init(path: AbsolutePath) throws {
        try initializeGit()

        var handle: Handle?
        try validate(git_repository_open_ext(&handle, path.asString, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil))
        self.init(handle: handle!, path: path)
    }

    deinit {
        git_repository_free(handle)
    }

    /// Lookup a tag in the repository by its object id.
    public func lookupTag(_ objectID: ObjectID) throws -> Tag {
        var tagHandle: Tag.Handle? = nil
        var oid = objectID.oid
        try validate(git_tag_lookup(&tagHandle, handle, &oid))
        return Tag(handle: handle)
    }

    /// Lists the tag names in the repository.
    public func listTagNames() throws -> [String] {
        var tagNames = git_strarray()
        try validate(git_tag_list(&tagNames, handle))
        defer { git_strarray_free(&tagNames)}
        return tagNames.asArray()
    }

    /// Returns the tags in the repository.
    public func getTags() throws -> [Tag] {
        struct Context {
            let repository: Repository
            var tags: [Tag]
            var error: Error?
        }

        var context = Context(repository: self, tags: [], error: nil)
        _ = try withUnsafeMutablePointer(to: &context) { context in
            try validate(git_tag_foreach(handle, { (name, oid, context) in
                let name = String(cString: name!)
                print("name: \(name)")
                let context = context!.assumingMemoryBound(to: Context.self)
                do {
                    let tag = try context.pointee.repository.lookupTag(ObjectID(oid: oid!.pointee))
                    context.pointee.tags.append(tag)
                    return 0
                } catch {
                    context.pointee.error = error
                    return 1
                }
            }, context))
        }

        if let error = context.error {
            throw error
        }

        return context.tags
    }

    /// Returns the branches in the repository.
    public func getBranches(_ type: Branch.Kind = .all) throws -> [Branch] {
        // Create a branch iterator.
        var iterator: OpaquePointer?
        try! validate(git_branch_iterator_new(&iterator, self.handle, type.git_branch_t))
        defer { git_branch_iterator_free(iterator) }

        var branches: [Branch] = []

        while true {
            var referenceHandle: Reference.Handle? = nil
            var branchType = GIT_BRANCH_ALL
            let result = try! validate(git_branch_next(&referenceHandle, &branchType, iterator!))

            // Check if there are any more branches.
            guard result != GIT_ITEROVER else { break }

            branches.append(Branch(handle: referenceHandle!))
        }

        return branches
    }

    public func resolveReference(fromName name: String) throws -> ObjectID {
        var oid = git_oid()
        _ = try name.withCString { name in
            try validate(git_reference_name_to_id(&oid, handle, name))
        }
        return ObjectID(oid: oid)
    }
}

extension Repository: CustomStringConvertible {
    public var description: String {
        return "<libgit: \(path.asString)>"
    }
}
