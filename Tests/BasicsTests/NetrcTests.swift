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
import Foundation

import Basics
import Testing

struct NetrcTests {
    /// should load machines for a given inline format
    @Test
    func loadMachinesInline() throws {
        let content = "machine example.com login anonymous password qwerty"

        let netrc = try NetrcParser.parse(content)
        #expect(netrc.machines.count == 1)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")

        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        #expect(authorization == Netrc.Authorization(login: "anonymous", password: "qwerty"))

        #expect(netrc.authorization(for: "http://example2.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "http://www.example2.com/resource.zip") == nil)
    }

    /// should load machines for a given multi-line format
    @Test
    func loadMachinesMultiLine() throws {
        let content = """
            machine example.com
            login anonymous
            password qwerty
            """

        let netrc = try NetrcParser.parse(content)
        #expect(netrc.machines.count == 1)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")

        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        #expect(authorization == Netrc.Authorization(login: "anonymous", password: "qwerty"))

        #expect(netrc.authorization(for: "http://example2.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "http://www.example2.com/resource.zip") == nil)
    }

    /// Should fall back to default machine when not matching host
    @Test
    func loadDefaultMachine() throws {
        let content = """
            machine example.com
            login anonymous
            password qwerty

            default
            login id
            password secret
            """

        let netrc = try NetrcParser.parse(content)
        #expect(netrc.machines.count == 2)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")

        let machine2 = try #require(netrc.machines.last)
        #expect(machine2.name == "default")
        #expect(machine2.login == "id")
        #expect(machine2.password == "secret")

        let authorization = netrc.authorization(for: "http://example2.com/resource.zip")
        #expect(authorization == Netrc.Authorization(login: "id", password: "secret"))
    }

    @Test
    func regexParsing() throws {
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
        #expect(netrc.machines.count == 3)

        #expect(netrc.machines[0].name == "machine")
        #expect(netrc.machines[0].login == "login")
        #expect(netrc.machines[0].password == "password")

        #expect(netrc.machines[1].name == "login")
        #expect(netrc.machines[1].login == "password")
        #expect(netrc.machines[1].password == "machine")

        #expect(netrc.machines[2].name == "default")
        #expect(netrc.machines[2].login == "id")
        #expect(netrc.machines[2].password == "secret")

        let authorization = netrc.authorization(for: "http://example2.com/resource.zip")
        #expect(authorization == Netrc.Authorization(login: "id", password: "secret"))
    }

    @Test
    func outOfOrderDefault() {
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

        #expect(throws: NetrcError.invalidDefaultMachinePosition) {
            try NetrcParser.parse(content)
        }
    }

    @Test
    func errorOnMultipleDefault() {
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

        #expect(throws: NetrcError.invalidDefaultMachinePosition) {
            try NetrcParser.parse(content)
        }
    }

    /// should load machines for a given multi-line format with comments
    @Test
    func loadMachinesMultilineComments() throws {
        let content = """
            ## This is a comment
            # This is another comment
            machine example.com # This is an inline comment
            login anonymous
            password qwerty # and # another #one
            """

        let machines = try NetrcParser.parse(content).machines
        #expect(machines.count == 1)

        let machine = try #require(machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")
    }

    /// should load machines for a given multi-line + whitespaces format
    @Test
    func loadMachinesMultilineWhitespaces() throws {
        let content = """
            machine  example.com login     anonymous
            password                  qwerty
            """

        let machines = try NetrcParser.parse(content).machines
        #expect(machines.count == 1)

        let machine = try #require(machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")
    }

    /// should load multiple machines for a given inline format
    @Test
    func loadMultipleMachinesInline() throws {
        let content = "machine example.com login anonymous password qwerty machine example2.com login anonymous2 password qwerty2"

        let netrc = try NetrcParser.parse(content)
        #expect(netrc.machines.count == 2)

        #expect(netrc.machines[0].name == "example.com")
        #expect(netrc.machines[0].login == "anonymous")
        #expect(netrc.machines[0].password == "qwerty")

        #expect(netrc.machines[1].name == "example2.com")
        #expect(netrc.machines[1].login == "anonymous2")
        #expect(netrc.machines[1].password == "qwerty2")
    }

    /// should load multiple machines for a given multi-line format
    @Test
    func loadMultipleMachinesMultiline() throws {
        let content = """
            machine  example.com login     anonymous
            password                  qwerty
            machine example2.com
            login anonymous2
            password qwerty2
            """

        let machines = try NetrcParser.parse(content).machines
        #expect(machines.count == 2)

        var machine = machines[0]
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")

        machine = machines[1]
        #expect(machine.name == "example2.com")
        #expect(machine.login == "anonymous2")
        #expect(machine.password == "qwerty2")
    }

    /// should throw error when machine parameter is missing
    @Test
    func errorMachineParameterMissing() throws {
        let content = "login anonymous password qwerty"

        #expect(throws: NetrcError.machineNotFound) {
            try NetrcParser.parse(content)
        }
    }

    /// should throw error for an empty machine values
    @Test
    func errorEmptyMachineValue() throws {
        let content = "machine"

        #expect(throws: NetrcError.machineNotFound) {
            try NetrcParser.parse(content)
        }
    }

    /// should throw error for an empty machine values
    @Test
    func emptyMachineValueFollowedByDefaultNoError() throws {
        let content = "machine default login id password secret"
        let netrc = try NetrcParser.parse(content)
        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        #expect(authorization == Netrc.Authorization(login: "id", password: "secret"))
    }

    /// should return authorization when config contains a given machine
    @Test
    func returnAuthorizationForMachineMatch() throws {
        let content = "machine example.com login anonymous password qwerty"

        let netrc = try NetrcParser.parse(content)
        let authorization = netrc.authorization(for: "http://example.com/resource.zip")
        #expect(authorization == Netrc.Authorization(login: "anonymous", password: "qwerty"))
    }

    @Test
    func returnNoAuthorizationForUnmatched() throws {
        let content = "machine example.com login anonymous password qwerty"
        let netrc = try NetrcParser.parse(content)
        #expect(netrc.authorization(for: "http://www.example.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "ftp.example.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "http://example2.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "http://www.example2.com/resource.zip") == nil)
    }

    /// should not return authorization when config does not contain a given machine
    @Test
    func noReturnAuthorizationForNoMachineMatch() throws {
        let content = "machine example.com login anonymous password qwerty"

        let netrc = try NetrcParser.parse(content)
        #expect(netrc.authorization(for: "https://example99.com") == nil)
        #expect(netrc.authorization(for: "http://www.example.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "ftp.example.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "http://example2.com/resource.zip") == nil)
        #expect(netrc.authorization(for: "http://www.example2.com/resource.zip") == nil)
    }

    /// Test case: https://www.ibm.com/support/knowledgecenter/en/ssw_aix_72/filesreference/netrc.html
    @Test
    func iBMDocumentation() throws {
        let content = "machine host1.austin.century.com login fred password bluebonnet"

        let netrc = try NetrcParser.parse(content)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "host1.austin.century.com")
        #expect(machine.login == "fred")
        #expect(machine.password == "bluebonnet")
    }

    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://gist.github.com/tpope/4247721
    @Test
    func noErrorTrailingAccountMacdefDefault() throws {
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

        #expect(netrc.machines.count == 4)

        #expect(netrc.machines[0].name == "api.heroku.com")
        #expect(netrc.machines[0].login == "my@email.com")
        #expect(netrc.machines[0].password == "01230123012301230123012301230123")

        #expect(netrc.machines[1].name == "api.github.com")
        #expect(netrc.machines[1].login == "somebody")
        #expect(netrc.machines[1].password == "something")

        #expect(netrc.machines[2].name == "ftp.server")
        #expect(netrc.machines[2].login == "abc")
        #expect(netrc.machines[2].password == "def")

        #expect(netrc.machines[3].name == "default")
        #expect(netrc.machines[3].login == "anonymous")
        #expect(netrc.machines[3].password == "my@email.com")
    }

    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://gist.github.com/tpope/4247721
    @Test
    func noErrorMixedAccount() throws {
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

        #expect(netrc.machines.count == 4)

        #expect(netrc.machines[0].name == "api.heroku.com")
        #expect(netrc.machines[0].login == "my@email.com")
        #expect(netrc.machines[0].password == "01230123012301230123012301230123")

        #expect(netrc.machines[1].name == "api.github.com")
        #expect(netrc.machines[1].login == "somebody")
        #expect(netrc.machines[1].password == "something")

        #expect(netrc.machines[2].name == "ftp.server")
        #expect(netrc.machines[2].login == "abc")
        #expect(netrc.machines[2].password == "def")

        #expect(netrc.machines[3].name == "default")
        #expect(netrc.machines[3].login == "anonymous")
        #expect(netrc.machines[3].password == "my@email.com")
    }

    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://renenyffenegger.ch/notes/Linux/fhs/home/username/_netrc
    @Test
    func noErrorMultipleMacdefAndComments() throws {
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

        #expect(netrc.machines.count == 2)

        #expect(netrc.machines[0].name == "ftp.foobar.baz")
        #expect(netrc.machines[0].login == "john")
        #expect(netrc.machines[0].password == "5ecr3t")

        #expect(netrc.machines[1].name == "other.server.org")
        #expect(netrc.machines[1].login == "fred")
        #expect(netrc.machines[1].password == "sunshine4ever")
    }

    @Test
    func comments() throws {
        let content = """
            # A comment at the beginning of the line
            machine example.com # Another comment
            login anonymous  # Another comment
            password qw#erty  # Another comment
            """

        let netrc = try NetrcParser.parse(content)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qw#erty")
    }

    @Test(
        arguments: [
            (testCase: "qwerty", expected: "qwerty"),
            (testCase: "qwe#rty", expected: "qwe#rty"),
            (testCase: "\"qwe#rty\"", expected: "qwe#rty"),
            (testCase: "\"qwe #rty\"", expected: "qwe #rty"),
            (testCase: "\"qwe# rty\"", expected: "qwe# rty"),
        ]
    )
    func allHashQuotingPermutations(testCase: String, expected: String) throws {
        let content = """
            machine example.com
            login \(testCase)
            password \(testCase)
            """
        let netrc = try NetrcParser.parse(content)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == expected)
        #expect(machine.password == expected)
    }

    @Test(
        arguments: [
            (testCase: "qwerty   # a comment", expected: "qwerty"),
            (testCase: "qwe#rty   # a comment", expected: "qwe#rty"),
            (testCase: "\"qwe#rty\"   # a comment", expected: "qwe#rty"),
            (testCase: "\"qwe #rty\"   # a comment", expected: "qwe #rty"),
            (testCase: "\"qwe# rty\"   # a comment", expected: "qwe# rty"),
        ]
    )
    func allCommentPermutations(testCase: String, expected: String) throws {
        let content = """
            machine example.com
            login \(testCase)
            password \(testCase)
            """
        let netrc = try NetrcParser.parse(content)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == expected)
        #expect(machine.password == expected)
    }

    @Test
    func quotedMachine() throws {
        let content = """
            machine "example.com"
            login anonymous
            password qwerty
            """

        let netrc = try NetrcParser.parse(content)

        let machine = try #require(netrc.machines.first)
        #expect(machine.name == "example.com")
        #expect(machine.login == "anonymous")
        #expect(machine.password == "qwerty")
    }
}
