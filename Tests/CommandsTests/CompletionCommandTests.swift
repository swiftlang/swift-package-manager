import Basics
import _InternalTestSupport
import XCTest

final class CompletionCommandTests: CommandsTestCase {

    private func execute(
        _ args: [String] = [],
        packagePath: AbsolutePath? = nil
    ) async throws -> (stdout: String, stderr: String) {
        return try await SwiftPM.Package.execute(args, packagePath: packagePath)
    }

    func testListExecutables() async throws {
        try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            let result = try await execute(["completion-tool", "list-executables"], packagePath: fixturePath)
            XCTAssertEqual(result.stdout, "exec1\nexec2\n")
        }
    }

    func testListExecutablesDifferentNames() async throws {
        try await fixture(name: "Miscellaneous/DifferentProductTargetName") { fixturePath in
            let result = try await execute(["completion-tool", "list-executables"], packagePath: fixturePath)
            XCTAssertEqual(result.stdout, "Foo\n")
        }
    }
}