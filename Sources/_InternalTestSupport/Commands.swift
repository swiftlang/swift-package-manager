import SPMBuildCore
import XCTest

public struct XFailCaseName {
    let testName: String
    let reason: String

    public init(_ testName: String, because reason: String) {
        self.testName = testName
        self.reason = reason
    }
}
open class BuildSystemProviderTestCase: XCTestCase {
    open var buildSystemProvider: BuildSystemProvider.Kind {
        fatalError("\(self) does not implement \(#function)")
    }

    open var xFailTestCaseNames: [XFailCaseName] {
        return []
    }

    override open func recordFailure(withDescription description: String, inFile filePath: String, atLine lineNumber: Int, expected: Bool) {
        // Get current test name:
        print("--->> In recordFailure: Test name is >>>\(self.name)<<<")

        if self.xFailTestCaseNames.map({ item in item.testName }).contains(self.name) {
            // do nothing
            print("--->> In recordFailure: Test name is >>>\(self.name)<<< is expected to fail, so mark as passed!!")
        } else {
            super.recordFailure(
                withDescription: description,
                inFile: filePath,
                atLine: lineNumber,
                expected: expected
            )
        }
    }
}
