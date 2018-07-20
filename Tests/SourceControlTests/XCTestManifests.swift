#if !os(macOS)
import XCTest

extension GitRepositoryTests {
    static let __allTests = [
        ("testAlternativeObjectStoreValidation", testAlternativeObjectStoreValidation),
        ("testAreIgnored", testAreIgnored),
        ("testAreIgnoredWithSpaceInRepoPath", testAreIgnoredWithSpaceInRepoPath),
        ("testBranchOperations", testBranchOperations),
        ("testCheckoutRevision", testCheckoutRevision),
        ("testCheckouts", testCheckouts),
        ("testFetch", testFetch),
        ("testGitFileView", testGitFileView),
        ("testGitRepositoryHash", testGitRepositoryHash),
        ("testHasUnpushedCommits", testHasUnpushedCommits),
        ("testProvider", testProvider),
        ("testRawRepository", testRawRepository),
        ("testRepositorySpecifier", testRepositorySpecifier),
        ("testSetRemote", testSetRemote),
        ("testSubmoduleRead", testSubmoduleRead),
        ("testSubmodules", testSubmodules),
        ("testUncommitedChanges", testUncommitedChanges),
    ]
}

extension InMemoryGitRepositoryTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testProvider", testProvider),
    ]
}

extension RepositoryManagerTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testParallelLookups", testParallelLookups),
        ("testPersistence", testPersistence),
        ("testReset", testReset),
        ("testSkipUpdate", testSkipUpdate),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(GitRepositoryTests.__allTests),
        testCase(InMemoryGitRepositoryTests.__allTests),
        testCase(RepositoryManagerTests.__allTests),
    ]
}
#endif
