import clibc
import Foundation
import Basic

private var isInitialized = false
private let lock = Lock()

/// Initialize libgit if necessary.
internal func initializeGit() throws {
    try lock.withLock {
        guard !isInitialized else { return }
        try dlopen(getGitLibraryPath(), 0)
        try validate(git_libgit2_init())
    }
}

/// Returns the location of the runtime libgit2 library.
private func getGitLibraryPath() throws -> String {
    //TODO: Calculate using pkg-config on Linux and xcode-select on macOS
    return "/Applications/Xcode-beta.app/Contents/Developer/usr/lib/libgit2.dylib"
}

/// Parses and validates a libgit error code.
/// - Returns: Returns a `git_error_code` value.
@discardableResult
internal func validate(_ errorCode: Int32) throws -> git_error_code {
    let result = git_error_code(errorCode)

    // Check that the result is OK or end of iteration.
    guard result.rawValue >= 0 || result == GIT_ITEROVER else {
        if let error = giterr_last() {
            throw GitError(
                code: result,
                class: git_error_t(UInt32(error.pointee.klass)),
                message: String(cString: error.pointee.message))
        } else {
            fatalError("no message?")
//            throw GitError.unknownError
        }
    }

    return result
}

extension git_strarray {
    internal func asArray() -> [String] {
        var array: [String] = []
        array.reserveCapacity(count)

        for index in 0..<count {
            array.append(String(cString: strings[index]!))
        }

        return array
    }
}
