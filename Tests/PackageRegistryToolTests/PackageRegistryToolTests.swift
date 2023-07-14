import Foundation
import XCTest
@testable import PackageRegistryTool

final class PackageRegistryToolTests: XCTestCase {

    func testCreateLoginURL() {
        let registryURL = URL(string: "https://packages.example.com")!

        XCTAssertEqual(try SwiftPackageRegistryTool.Login.loginURL(from: registryURL, loginAPIPath: nil).absoluteString, "https://packages.example.com/login")

        XCTAssertEqual(try SwiftPackageRegistryTool.Login.loginURL(from: registryURL, loginAPIPath: "/secret-sign-in").absoluteString, "https://packages.example.com/secret-sign-in")

    }

    func testCreateLoginURLMaintainsPort() {
        let registryURL = URL(string: "https://packages.example.com:8081")!

        XCTAssertEqual(try SwiftPackageRegistryTool.Login.loginURL(from: registryURL, loginAPIPath: nil).absoluteString, "https://packages.example.com:8081/login")

        XCTAssertEqual(try SwiftPackageRegistryTool.Login.loginURL(from: registryURL, loginAPIPath: "/secret-sign-in").absoluteString, "https://packages.example.com:8081/secret-sign-in")
    }

}
