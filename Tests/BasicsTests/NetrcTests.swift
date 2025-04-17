//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import XCTest

class NetrcTests: XCTestCase {
    /// should load machines for a given inline format
    func testLoadMachinesInline() throws {
        let content = "machine example.com login anonymous password qwerty"

        let netrc = try NetrcParser.parse(content)
        XCTAssertEqual(netrc.machines.count, 1)

        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")

        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        XCTAssertEqual(authorization, Netrc.Authorization(login: "anonymous", password: "qwerty"))

        XCTAssertNil(netrc.authorization(for: "http://example2.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "http://www.example2.com/resource.zip"))
    }

    /// should load machines for a given multi-line format
    func testLoadMachinesMultiLine() throws {
        let content = """
                    machine example.com
                    login anonymous
                    password qwerty
                    """

        let netrc = try NetrcParser.parse(content)
        XCTAssertEqual(netrc.machines.count, 1)

        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")

        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        XCTAssertEqual(authorization, Netrc.Authorization(login: "anonymous", password: "qwerty"))

        XCTAssertNil(netrc.authorization(for: "http://example2.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "http://www.example2.com/resource.zip"))
    }

    /// Should fall back to default machine when not matching host
    func testLoadDefaultMachine() throws {
        let content = """
                    machine example.com
                    login anonymous
                    password qwerty

                    default
                    login id
                    password secret
                    """

        let netrc = try NetrcParser.parse(content)
        XCTAssertEqual(netrc.machines.count, 2)

        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")

        let machine2 = netrc.machines.last
        XCTAssertEqual(machine2?.name, "default")
        XCTAssertEqual(machine2?.login, "id")
        XCTAssertEqual(machine2?.password, "secret")

        let authorization = netrc.authorization(for: "http://example2.com/resource.zip")
        XCTAssertEqual(authorization, Netrc.Authorization(login: "id", password: "secret"))
    }

    func testRegexParsing() throws {
        let content = """
                    machine machine
                    login login
                    password password

                    machine login
                    password machine
                    login password

                    default machine
                    login id
                    password secret

                    machinemachine machine
                    loginlogin id
                    passwordpassword secret

                    default
                    login id
                    password secret
                    """

        let netrc = try NetrcParser.parse(content)
        XCTAssertEqual(netrc.machines.count, 3)

        XCTAssertEqual(netrc.machines[0].name, "machine")
        XCTAssertEqual(netrc.machines[0].login, "login")
        XCTAssertEqual(netrc.machines[0].password, "password")

        XCTAssertEqual(netrc.machines[1].name, "login")
        XCTAssertEqual(netrc.machines[1].login, "password")
        XCTAssertEqual(netrc.machines[1].password, "machine")

        XCTAssertEqual(netrc.machines[2].name, "default")
        XCTAssertEqual(netrc.machines[2].login, "id")
        XCTAssertEqual(netrc.machines[2].password, "secret")

        let authorization = netrc.authorization(for: "http://example2.com/resource.zip")
        XCTAssertEqual(authorization, Netrc.Authorization(login: "id", password: "secret"))
    }

    func testOutOfOrderDefault() {
        let content = """
                    machine machine
                    login login
                    password password

                    machine login
                    password machine
                    login password

                    default
                    login id
                    password secret

                    machine machine
                    login id
                    password secret
                    """

        XCTAssertThrowsError(try NetrcParser.parse(content)) { error in
            XCTAssertEqual(error as? NetrcError, .invalidDefaultMachinePosition)
        }
    }

    func testErrorOnMultipleDefault() {
        let content = """
                    machine machine
                    login login
                    password password

                    machine login
                    password machine
                    login password

                    default
                    login id
                    password secret

                    machine machine
                    login id
                    password secret

                    default
                    login di
                    password terces
                    """

        XCTAssertThrowsError(try NetrcParser.parse(content)) { error in
            XCTAssertEqual(error as? NetrcError, .invalidDefaultMachinePosition)
        }
    }

    /// should load machines for a given multi-line format with comments
    func testLoadMachinesMultilineComments() throws {
        let content = """
                    ## This is a comment
                    # This is another comment
                    machine example.com # This is an inline comment
                    login anonymous
                    password qwerty # and # another #one
                    """

        let machines = try NetrcParser.parse(content).machines
        XCTAssertEqual(machines.count, 1)

        let machine = machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
    }

    /// should load machines for a given multi-line + whitespaces format
    func testLoadMachinesMultilineWhitespaces() throws {
        let content = """
                    machine  example.com login     anonymous
                    password                  qwerty
                    """

        let machines = try NetrcParser.parse(content).machines
        XCTAssertEqual(machines.count, 1)

        let machine = machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
    }

    /// should load multiple machines for a given inline format
    func testLoadMultipleMachinesInline() throws {
        let content = "machine example.com login anonymous password qwerty machine example2.com login anonymous2 password qwerty2"

        let netrc = try NetrcParser.parse(content)
        XCTAssertEqual(netrc.machines.count, 2)

        XCTAssertEqual(netrc.machines[0].name, "example.com")
        XCTAssertEqual(netrc.machines[0].login, "anonymous")
        XCTAssertEqual(netrc.machines[0].password, "qwerty")

        XCTAssertEqual(netrc.machines[1].name, "example2.com")
        XCTAssertEqual(netrc.machines[1].login, "anonymous2")
        XCTAssertEqual(netrc.machines[1].password, "qwerty2")
    }

    /// should load multiple machines for a given multi-line format
    func testLoadMultipleMachinesMultiline() throws {
        let content = """
                    machine  example.com login     anonymous
                    password                  qwerty
                    machine example2.com
                    login anonymous2
                    password qwerty2
                    """

        let machines = try NetrcParser.parse(content).machines
        XCTAssertEqual(machines.count, 2)

        var machine = machines[0]
        XCTAssertEqual(machine.name, "example.com")
        XCTAssertEqual(machine.login, "anonymous")
        XCTAssertEqual(machine.password, "qwerty")

        machine = machines[1]
        XCTAssertEqual(machine.name, "example2.com")
        XCTAssertEqual(machine.login, "anonymous2")
        XCTAssertEqual(machine.password, "qwerty2")
    }

    /// should throw error when machine parameter is missing
    func testErrorMachineParameterMissing() throws {
        let content = "login anonymous password qwerty"

        XCTAssertThrowsError(try NetrcParser.parse(content)) { error in
            XCTAssertEqual(error as? NetrcError, .machineNotFound)
        }
    }

    /// should throw error for an empty machine values
    func testErrorEmptyMachineValue() throws {
        let content = "machine"

        XCTAssertThrowsError(try NetrcParser.parse(content)) { error in
            XCTAssertEqual(error as? NetrcError, .machineNotFound)
        }
    }

    /// should throw error for an empty machine values
    func testEmptyMachineValueFollowedByDefaultNoError() throws {
        let content = "machine default login id password secret"
        let netrc = try NetrcParser.parse(content)
        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        XCTAssertEqual(authorization, Netrc.Authorization(login: "id", password: "secret"))
    }

    /// should return authorization when config contains a given machine
    func testReturnAuthorizationForMachineMatch() throws {
        let content = "machine example.com login anonymous password qwerty"

        let netrc = try NetrcParser.parse(content)
        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        XCTAssertEqual(authorization, Netrc.Authorization(login: "anonymous", password: "qwerty"))
    }

    func testReturnNoAuthorizationForUnmatched() throws {
        let content = "machine example.com login anonymous password qwerty"
        let netrc = try NetrcParser.parse(content)
        XCTAssertNil(netrc.authorization(for: "http://www.example.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "ftp.example.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "http://example2.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "http://www.example2.com/resource.zip"))
    }

    /// should not return authorization when config does not contain a given machine
    func testNoReturnAuthorizationForNoMachineMatch() throws {
        let content = "machine example.com login anonymous password qwerty"

        let netrc = try NetrcParser.parse(content)
        XCTAssertNil(netrc.authorization(for: "https://example99.com"))
        XCTAssertNil(netrc.authorization(for: "http://www.example.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "ftp.example.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "http://example2.com/resource.zip"))
        XCTAssertNil(netrc.authorization(for: "http://www.example2.com/resource.zip"))
    }

    /// Test case: https://www.ibm.com/support/knowledgecenter/en/ssw_aix_72/filesreference/netrc.html
    func testIBMDocumentation() throws {
        let content = "machine host1.austin.century.com login fred password bluebonnet"

        let netrc = try NetrcParser.parse(content)

        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "host1.austin.century.com")
        XCTAssertEqual(machine?.login, "fred")
        XCTAssertEqual(machine?.password, "bluebonnet")
    }

    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://gist.github.com/tpope/4247721
    func testNoErrorTrailingAccountMacdefDefault() throws {
        let content = """
            machine api.heroku.com
              login my@email.com
              password 01230123012301230123012301230123

            machine api.github.com password something login somebody

            machine ftp.server login abc password def account ghi macdef somemacro
            cd somehwhere
            continues until end of paragraph

            default login anonymous password my@email.com
            """

        let netrc = try NetrcParser.parse(content)

        XCTAssertEqual(netrc.machines.count, 4)

        XCTAssertEqual(netrc.machines[0].name, "api.heroku.com")
        XCTAssertEqual(netrc.machines[0].login, "my@email.com")
        XCTAssertEqual(netrc.machines[0].password, "01230123012301230123012301230123")

        XCTAssertEqual(netrc.machines[1].name, "api.github.com")
        XCTAssertEqual(netrc.machines[1].login, "somebody")
        XCTAssertEqual(netrc.machines[1].password, "something")

        XCTAssertEqual(netrc.machines[2].name, "ftp.server")
        XCTAssertEqual(netrc.machines[2].login, "abc")
        XCTAssertEqual(netrc.machines[2].password, "def")

        XCTAssertEqual(netrc.machines[3].name, "default")
        XCTAssertEqual(netrc.machines[3].login, "anonymous")
        XCTAssertEqual(netrc.machines[3].password, "my@email.com")
    }

    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://gist.github.com/tpope/4247721
    func testNoErrorMixedAccount() throws {
        let content = """
            machine api.heroku.com
              login my@email.com
              password 01230123012301230123012301230123

            machine api.github.com password something account ghi login somebody

            machine ftp.server login abc account ghi password def macdef somemacro
            cd somehwhere
            continues until end of paragraph

            default login anonymous password my@email.com
            """

        let netrc = try NetrcParser.parse(content)

        XCTAssertEqual(netrc.machines.count, 4)

        XCTAssertEqual(netrc.machines[0].name, "api.heroku.com")
        XCTAssertEqual(netrc.machines[0].login, "my@email.com")
        XCTAssertEqual(netrc.machines[0].password, "01230123012301230123012301230123")

        XCTAssertEqual(netrc.machines[1].name, "api.github.com")
        XCTAssertEqual(netrc.machines[1].login, "somebody")
        XCTAssertEqual(netrc.machines[1].password, "something")

        XCTAssertEqual(netrc.machines[2].name, "ftp.server")
        XCTAssertEqual(netrc.machines[2].login, "abc")
        XCTAssertEqual(netrc.machines[2].password, "def")

        XCTAssertEqual(netrc.machines[3].name, "default")
        XCTAssertEqual(netrc.machines[3].login, "anonymous")
        XCTAssertEqual(netrc.machines[3].password, "my@email.com")
    }

    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://renenyffenegger.ch/notes/Linux/fhs/home/username/_netrc
    func testNoErrorMultipleMacdefAndComments() throws {
        let content = """
            machine  ftp.foobar.baz
            login    john
            password 5ecr3t

            macdef   getmyfile       # define a macro (here named 'getmyfile')
            cd /abc/defghi/jklm      # The macro can be executed in ftp client
            get myFile.txt           # by prepending macro name with $ sign
            quit

            macdef   init            # macro init is searched for when
            binary                   # ftp connects to server.

            machine  other.server.org
            login    fred
            password sunshine4ever
            """

        let netrc = try NetrcParser.parse(content)

        XCTAssertEqual(netrc.machines.count, 2)

        XCTAssertEqual(netrc.machines[0].name, "ftp.foobar.baz")
        XCTAssertEqual(netrc.machines[0].login, "john")
        XCTAssertEqual(netrc.machines[0].password, "5ecr3t")

        XCTAssertEqual(netrc.machines[1].name, "other.server.org")
        XCTAssertEqual(netrc.machines[1].login, "fred")
        XCTAssertEqual(netrc.machines[1].password, "sunshine4ever")
    }

    func testComments() throws {
        let content = """
            # A comment at the beginning of the line
            machine example.com # Another comment
            login anonymous  # Another comment
            password qw#erty  # Another comment
            """

        let netrc = try NetrcParser.parse(content)

        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qw#erty")
    }

    // TODO: These permutation tests would be excellent swift-testing parameterized tests.
    func testAllHashQuotingPermutations() throws {
        let cases = [
            ("qwerty", "qwerty"),
            ("qwe#rty", "qwe#rty"),
            ("\"qwe#rty\"", "qwe#rty"),
            ("\"qwe #rty\"", "qwe #rty"),
            ("\"qwe# rty\"", "qwe# rty"),
        ]

        for (testCase, expected) in cases {
            let content = """
                machine example.com
                login \(testCase)
                password \(testCase)
                """
            let netrc = try NetrcParser.parse(content)

            let machine = netrc.machines.first
            XCTAssertEqual(machine?.name, "example.com")
            XCTAssertEqual(machine?.login, expected, "Expected login \(testCase) to parse as \(expected)")
            XCTAssertEqual(machine?.password, expected, "Expected \(testCase) to parse as \(expected)")
        }
    }

    func testAllCommentPermutations() throws {
        let cases = [
            ("qwerty   # a comment", "qwerty"),
            ("qwe#rty   # a comment", "qwe#rty"),
            ("\"qwe#rty\"   # a comment", "qwe#rty"),
            ("\"qwe #rty\"   # a comment", "qwe #rty"),
            ("\"qwe# rty\"   # a comment", "qwe# rty"),
        ]

        for (testCase, expected) in cases {
            let content = """
                machine example.com
                login \(testCase)
                password \(testCase)
                """
            let netrc = try NetrcParser.parse(content)

            let machine = netrc.machines.first
            XCTAssertEqual(machine?.name, "example.com")
            XCTAssertEqual(machine?.login, expected, "Expected login \(testCase) to parse as \(expected)")
            XCTAssertEqual(machine?.password, expected, "Expected password \(testCase) to parse as \(expected)")
        }
    }

    func testQuotedMachine() throws {
        let content = """
            machine "example.com"
            login anonymous
            password qwerty
            """

        let netrc = try NetrcParser.parse(content)

        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
    }
}
