import XCTest
import TSCUtility

#if os(macOS)
@available(macOS 10.13, *)
/// Netrc feature depends upon `NSTextCheckingResult.range(withName name: String) -> NSRange`,
/// which is only available in macOS 10.13+ at this time.
class NetrcTests: XCTestCase {
    /// should load machines for a given inline format
    func testLoadMachinesInline() {
        let content = "machine example.com login anonymous password qwerty"
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        XCTAssertEqual(netrc.machines.count, 1)
        
        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
        
        let authorization = netrc.authorization(for: URL(string: "http://example.com/resource.zip")!)
        XCTAssertNotNil(authorization)
        
        let authData = "anonymous:qwerty".data(using: .utf8)!
        XCTAssertEqual(authorization, "Basic \(authData.base64EncodedString())")
        
        XCTAssertNil(netrc.authorization(for: URL(string: "http://example2.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://www.example2.com/resource.zip")!))
    }
    
    /// should load machines for a given multi-line format
    func testLoadMachinesMultiLine() {
        let content = """
                    machine example.com
                    login anonymous
                    password qwerty
                    """
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        XCTAssertEqual(netrc.machines.count, 1)
        
        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
        
        let authorization = netrc.authorization(for: URL(string: "http://example.com/resource.zip")!)
        XCTAssertNotNil(authorization)
        
        let authData = "anonymous:qwerty".data(using: .utf8)!
        XCTAssertEqual(authorization, "Basic \(authData.base64EncodedString())")
        
        XCTAssertNil(netrc.authorization(for: URL(string: "http://example2.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://www.example2.com/resource.zip")!))
    }
    
    /// Should fall back to default machine when not matching host
    func testLoadDefaultMachine() {
        let content = """
                    machine example.com
                    login anonymous
                    password qwerty

                    default
                    login id
                    password secret
                    """
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        XCTAssertEqual(netrc.machines.count, 2)
        
        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
        
        let machine2 = netrc.machines.last
        XCTAssertEqual(machine2?.name, "default")
        XCTAssertEqual(machine2?.login, "id")
        XCTAssertEqual(machine2?.password, "secret")
        
        let authorization = netrc.authorization(for: URL(string: "http://example2.com/resource.zip")!)
        XCTAssertNotNil(authorization)
        
        let authData = "id:secret".data(using: .utf8)!
        XCTAssertEqual(authorization, "Basic \(authData.base64EncodedString())")
    }
    
    func testRegexParsing() {
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
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
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
        
        let authorization = netrc.authorization(for: URL(string: "http://example2.com/resource.zip")!)
        XCTAssertNotNil(authorization)
        
        let authData = "id:secret".data(using: .utf8)!
        XCTAssertEqual(authorization, "Basic \(authData.base64EncodedString())")
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
        
        guard case .failure(.invalidDefaultMachinePosition) = Netrc.from(content) else { return XCTFail() }
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
        
        guard case .failure(.invalidDefaultMachinePosition) = Netrc.from(content) else { return XCTFail() }
    }
    
    /// should load machines for a given multi-line format with comments
    func testLoadMachinesMultilineComments() {
        let content = """
                    ## This is a comment
                    # This is another comment
                    machine example.com # This is an inline comment
                    login anonymous
                    password qwerty # and # another #one
                    """
        
        let machines = try? Netrc.from(content).get().machines
        XCTAssertEqual(machines?.count, 1)
        
        let machine = machines?.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
    }
    
    /// should load machines for a given multi-line + whitespaces format
    func testLoadMachinesMultilineWhitespaces() {
        let content = """
                    machine  example.com login     anonymous
                    password                  qwerty
                    """
        
        let machines = try? Netrc.from(content).get().machines
        XCTAssertEqual(machines?.count, 1)
        
        let machine = machines?.first
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
    }
    
    /// should load multiple machines for a given inline format
    func testLoadMultipleMachinesInline() {
        let content = "machine example.com login anonymous password qwerty machine example2.com login anonymous2 password qwerty2"
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        XCTAssertEqual(netrc.machines.count, 2)
        
        XCTAssertEqual(netrc.machines[0].name, "example.com")
        XCTAssertEqual(netrc.machines[0].login, "anonymous")
        XCTAssertEqual(netrc.machines[0].password, "qwerty")
        
        XCTAssertEqual(netrc.machines[1].name, "example2.com")
        XCTAssertEqual(netrc.machines[1].login, "anonymous2")
        XCTAssertEqual(netrc.machines[1].password, "qwerty2")
    }
    
    /// should load multiple machines for a given multi-line format
    func testLoadMultipleMachinesMultiline() {
        let content = """
                    machine  example.com login     anonymous
                    password                  qwerty
                    machine example2.com
                    login anonymous2
                    password qwerty2
                    """
        
        let machines = try? Netrc.from(content).get().machines
        XCTAssertEqual(machines?.count, 2)
        
        var machine = machines?[0]
        XCTAssertEqual(machine?.name, "example.com")
        XCTAssertEqual(machine?.login, "anonymous")
        XCTAssertEqual(machine?.password, "qwerty")
        
        machine = machines?[1]
        XCTAssertEqual(machine?.name, "example2.com")
        XCTAssertEqual(machine?.login, "anonymous2")
        XCTAssertEqual(machine?.password, "qwerty2")
    }
    
    /// should throw error when machine parameter is missing
    func testErrorMachineParameterMissing() {
        let content = "login anonymous password qwerty"
        
        guard case .failure(.machineNotFound) = Netrc.from(content) else {
            return XCTFail("Expected machineNotFound error")
        }
    }
    
    /// should throw error for an empty machine values
    func testErrorEmptyMachineValue() {
        let content = "machine"
        
        guard case .failure(.machineNotFound) = Netrc.from(content) else {
            return XCTFail("Expected machineNotFound error")
        }
    }
    
    /// should throw error for an empty machine values
    func testEmptyMachineValueFollowedByDefaultNoError() {
        let content = "machine default login id password secret"
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        let authorization = netrc.authorization(for: URL(string: "http://example.com/resource.zip")!)
        let authData = "id:secret".data(using: .utf8)!
        XCTAssertNotNil(authorization)
        XCTAssertEqual(authorization, "Basic \(authData.base64EncodedString())")
    }
    
    /// should return authorization when config contains a given machine
    func testReturnAuthorizationForMachineMatch() {
        let content = "machine example.com login anonymous password qwerty"
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        
        let authorization = netrc.authorization(for: URL(string: "http://example.com/resource.zip")!)
        let authData = "anonymous:qwerty".data(using: .utf8)!
        XCTAssertNotNil(authorization)
        XCTAssertEqual(authorization, "Basic \(authData.base64EncodedString())")
    }
    
    func testReturnNoAuthorizationForUnmatched() {
        let content = "machine example.com login anonymous password qwerty"
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        XCTAssertNil(netrc.authorization(for: URL(string: "http://www.example.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "ftp.example.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://example2.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://www.example2.com/resource.zip")!))
    }
    
    /// should not return authorization when config does not contain a given machine
    func testNoReturnAuthorizationForNoMachineMatch() {
        let content = "machine example.com login anonymous password qwerty"
        
        guard case .success(let netrc) = Netrc.from(content) else { return XCTFail() }
        XCTAssertNil(netrc.authorization(for: URL(string: "https://example99.com")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://www.example.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "ftp.example.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://example2.com/resource.zip")!))
        XCTAssertNil(netrc.authorization(for: URL(string: "http://www.example2.com/resource.zip")!))
    }
    
    /// Test case: https://www.ibm.com/support/knowledgecenter/en/ssw_aix_72/filesreference/netrc.html
    func testIBMDocumentation() {
        let content = "machine host1.austin.century.com login fred password bluebonnet"
        
        guard let netrc = try? Netrc.from(content).get() else {
            return XCTFail()
        }
        
        let machine = netrc.machines.first
        XCTAssertEqual(machine?.name, "host1.austin.century.com")
        XCTAssertEqual(machine?.login, "fred")
        XCTAssertEqual(machine?.password, "bluebonnet")
    }
    
    /// Should not fail on presence of `account`, `macdef`, `default`
    /// test case: https://gist.github.com/tpope/4247721
    func testNoErrorTrailingAccountMacdefDefault() {
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
        
        guard let netrc = try? Netrc.from(content).get() else {
            return XCTFail()
        }
        
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
    func testNoErrorMixedAccount() {
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
        
        guard let netrc = try? Netrc.from(content).get() else {
            return XCTFail()
        }
        
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
    func testNoErrorMultipleMacdefAndComments() {
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
        
        guard let netrc = try? Netrc.from(content).get() else {
            return XCTFail()
        }
        
        XCTAssertEqual(netrc.machines.count, 2)
        
        XCTAssertEqual(netrc.machines[0].name, "ftp.foobar.baz")
        XCTAssertEqual(netrc.machines[0].login, "john")
        XCTAssertEqual(netrc.machines[0].password, "5ecr3t")
        
        XCTAssertEqual(netrc.machines[1].name, "other.server.org")
        XCTAssertEqual(netrc.machines[1].login, "fred")
        XCTAssertEqual(netrc.machines[1].password, "sunshine4ever")
    }
}
#endif
