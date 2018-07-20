#if !os(macOS)
import XCTest

extension AwaitTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension ByteStringTests {
    static let __allTests = [
        ("testAccessors", testAccessors),
        ("testAsString", testAsString),
        ("testByteStreamable", testByteStreamable),
        ("testDescription", testDescription),
        ("testHashable", testHashable),
        ("testInitializers", testInitializers),
    ]
}

extension CStringArrayTests {
    static let __allTests = [
        ("testInitialization", testInitialization),
    ]
}

extension CacheableSequenceTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension CollectionAlgorithmsTests {
    static let __allTests = [
        ("testFindDuplicates", testFindDuplicates),
        ("testRIndex", testRIndex),
    ]
}

extension CollectionExtensionsTests {
    static let __allTests = [
        ("testOnly", testOnly),
    ]
}

extension ConditionTests {
    static let __allTests = [
        ("testBroadcast", testBroadcast),
        ("testSignal", testSignal),
        ("testWaitUntil", testWaitUntil),
    ]
}

extension DeltaAlgorithmTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension DiagnosticsEngineTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testHandlers", testHandlers),
        ("testMerging", testMerging),
    ]
}

extension DictionaryExtensionTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testCreateDictionary", testCreateDictionary),
    ]
}

extension DictionaryLiteralExtensionsTests {
    static let __allTests = [
        ("testDescription", testDescription),
        ("testEquality", testEquality),
    ]
}

extension EditDistanceTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension FileSystemTests {
    static let __allTests = [
        ("testInMemoryBasics", testInMemoryBasics),
        ("testInMemoryCreateDirectory", testInMemoryCreateDirectory),
        ("testInMemoryFsCopy", testInMemoryFsCopy),
        ("testInMemoryReadWriteFile", testInMemoryReadWriteFile),
        ("testInMemRemoveFileTree", testInMemRemoveFileTree),
        ("testLocalBasics", testLocalBasics),
        ("testLocalCreateDirectory", testLocalCreateDirectory),
        ("testLocalExistsSymlink", testLocalExistsSymlink),
        ("testLocalReadWriteFile", testLocalReadWriteFile),
        ("testRemoveFileTree", testRemoveFileTree),
        ("testRootedFileSystem", testRootedFileSystem),
        ("testSetAttribute", testSetAttribute),
    ]
}

extension GraphAlgorithmsTests {
    static let __allTests = [
        ("testCycleDetection", testCycleDetection),
        ("testTopologicalSort", testTopologicalSort),
        ("testTransitiveClosure", testTransitiveClosure),
    ]
}

extension JSONMapperTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testErrors", testErrors),
    ]
}

extension JSONTests {
    static let __allTests = [
        ("testDecoding", testDecoding),
        ("testEncoding", testEncoding),
        ("testPrettyPrinting", testPrettyPrinting),
        ("testStringInitalizer", testStringInitalizer),
    ]
}

extension KeyedPairTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension LazyCacheTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension LockTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testFileLock", testFileLock),
    ]
}

extension ObjectIdentifierProtocolTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension OrderedSetTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension OutputByteStreamTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testBufferCorrectness", testBufferCorrectness),
        ("testFormattedOutput", testFormattedOutput),
        ("testJSONEncoding", testJSONEncoding),
        ("testLocalFileStream", testLocalFileStream),
        ("testStreamOperator", testStreamOperator),
        ("testThreadSafeStream", testThreadSafeStream),
    ]
}

extension POSIXTests {
    static let __allTests = [
        ("testFileStatus", testFileStatus),
    ]
}

extension PathShimTests {
    static let __allTests = [
        ("testCurrentWorkingDirectory", testCurrentWorkingDirectory),
        ("testRescursiveDirectoryCreation", testRescursiveDirectoryCreation),
        ("testResolvingSymlinks", testResolvingSymlinks),
    ]
}

extension PathTests {
    static let __allTests = [
        ("testAbsolutePathValidation", testAbsolutePathValidation),
        ("testBaseNameExtraction", testBaseNameExtraction),
        ("testBasics", testBasics),
        ("testCodable", testCodable),
        ("testCombinationsAndEdgeCases", testCombinationsAndEdgeCases),
        ("testComparison", testComparison),
        ("testConcatenation", testConcatenation),
        ("testContains", testContains),
        ("testDirectoryNameExtraction", testDirectoryNameExtraction),
        ("testDotDotPathComponents", testDotDotPathComponents),
        ("testDotPathComponents", testDotPathComponents),
        ("testParentDirectory", testParentDirectory),
        ("testPathComponents", testPathComponents),
        ("testRelativePathFromAbsolutePaths", testRelativePathFromAbsolutePaths),
        ("testRelativePathValidation", testRelativePathValidation),
        ("testRepeatedPathSeparators", testRepeatedPathSeparators),
        ("testStringInitialization", testStringInitialization),
        ("testStringLiteralInitialization", testStringLiteralInitialization),
        ("testSuffixExtraction", testSuffixExtraction),
        ("testTrailingPathSeparators", testTrailingPathSeparators),
    ]
}

extension ProcessSetTests {
    static let __allTests = [
        ("testSigInt", testSigInt),
        ("testSigKillEscalation", testSigKillEscalation),
    ]
}

extension ProcessTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testCheckNonZeroExit", testCheckNonZeroExit),
        ("testFindExecutable", testFindExecutable),
        ("testNonExecutableLaunch", testNonExecutableLaunch),
        ("testPopen", testPopen),
        ("testSignals", testSignals),
        ("testStdoutStdErr", testStdoutStdErr),
        ("testThreadSafetyOnWaitUntilExit", testThreadSafetyOnWaitUntilExit),
    ]
}

extension RegExTests {
    static let __allTests = [
        ("testErrors", testErrors),
        ("testMatchGroups", testMatchGroups),
    ]
}

extension ResultTests {
    static let __allTests = [
        ("testAnyError", testAnyError),
        ("testBasics", testBasics),
        ("testFlatMap", testFlatMap),
        ("testMap", testMap),
        ("testMapAny", testMapAny),
    ]
}

extension SHA256Tests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testLargeData", testLargeData),
    ]
}

extension SortedArrayTests {
    static let __allTests = [
        ("testSortedArrayInAscendingOrder", testSortedArrayInAscendingOrder),
        ("testSortedArrayInDescendingOrder", testSortedArrayInDescendingOrder),
        ("testSortedArrayInsertIntoSmallerArray", testSortedArrayInsertIntoSmallerArray),
        ("testSortedArrayInsertSlice", testSortedArrayInsertSlice),
        ("testSortedArrayWithValues", testSortedArrayWithValues),
    ]
}

extension StringConversionTests {
    static let __allTests = [
        ("testShellEscaped", testShellEscaped),
    ]
}

extension SyncronizedQueueTests {
    static let __allTests = [
        ("testMultipleProducerConsumer", testMultipleProducerConsumer),
        ("testMultipleProducerConsumer2", testMultipleProducerConsumer2),
        ("testSingleProducerConsumer", testSingleProducerConsumer),
    ]
}

extension TemporaryFileTests {
    static let __allTests = [
        ("testBasicReadWrite", testBasicReadWrite),
        ("testBasicTemporaryDirectory", testBasicTemporaryDirectory),
        ("testCanCreateUniqueTempDirectories", testCanCreateUniqueTempDirectories),
        ("testCanCreateUniqueTempFiles", testCanCreateUniqueTempFiles),
        ("testLeaks", testLeaks),
        ("testNoCleanupTemporaryFile", testNoCleanupTemporaryFile),
    ]
}

extension TerminalControllerTests {
    static let __allTests = [
        ("testBasic", testBasic),
    ]
}

extension ThreadTests {
    static let __allTests = [
        ("testMultipleThread", testMultipleThread),
        ("testNotDeinitBeforeExecutingTask", testNotDeinitBeforeExecutingTask),
        ("testSingleThread", testSingleThread),
    ]
}

extension TupleTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension WalkTests {
    static let __allTests = [
        ("testNonRecursive", testNonRecursive),
        ("testRecursive", testRecursive),
        ("testSymlinksNotWalked", testSymlinksNotWalked),
        ("testWalkingADirectorySymlinkResolvesOnce", testWalkingADirectorySymlinkResolvesOnce),
    ]
}

extension miscTests {
    static let __allTests = [
        ("testEmptyEnvSearchPaths", testEmptyEnvSearchPaths),
        ("testEnvSearchPaths", testEnvSearchPaths),
        ("testExecutableLookup", testExecutableLookup),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AwaitTests.__allTests),
        testCase(ByteStringTests.__allTests),
        testCase(CStringArrayTests.__allTests),
        testCase(CacheableSequenceTests.__allTests),
        testCase(CollectionAlgorithmsTests.__allTests),
        testCase(CollectionExtensionsTests.__allTests),
        testCase(ConditionTests.__allTests),
        testCase(DeltaAlgorithmTests.__allTests),
        testCase(DiagnosticsEngineTests.__allTests),
        testCase(DictionaryExtensionTests.__allTests),
        testCase(DictionaryLiteralExtensionsTests.__allTests),
        testCase(EditDistanceTests.__allTests),
        testCase(FileSystemTests.__allTests),
        testCase(GraphAlgorithmsTests.__allTests),
        testCase(JSONMapperTests.__allTests),
        testCase(JSONTests.__allTests),
        testCase(KeyedPairTests.__allTests),
        testCase(LazyCacheTests.__allTests),
        testCase(LockTests.__allTests),
        testCase(ObjectIdentifierProtocolTests.__allTests),
        testCase(OrderedSetTests.__allTests),
        testCase(OutputByteStreamTests.__allTests),
        testCase(POSIXTests.__allTests),
        testCase(PathShimTests.__allTests),
        testCase(PathTests.__allTests),
        testCase(ProcessSetTests.__allTests),
        testCase(ProcessTests.__allTests),
        testCase(RegExTests.__allTests),
        testCase(ResultTests.__allTests),
        testCase(SHA256Tests.__allTests),
        testCase(SortedArrayTests.__allTests),
        testCase(StringConversionTests.__allTests),
        testCase(SyncronizedQueueTests.__allTests),
        testCase(TemporaryFileTests.__allTests),
        testCase(TerminalControllerTests.__allTests),
        testCase(ThreadTests.__allTests),
        testCase(TupleTests.__allTests),
        testCase(WalkTests.__allTests),
        testCase(miscTests.__allTests),
    ]
}
#endif
