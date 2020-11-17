import Foundation
import TSCBasic

/// Supplies `Authorization` header, typically to be appended to `URLRequest`
public protocol AuthorizationProviding {
    /// Optional `Authorization` header, likely added to `URLRequest`
    func authorization(for url: Foundation.URL) -> String?
}

extension AuthorizationProviding {
    public func authorization(for url: Foundation.URL) -> String? {
        return nil
    }
}

#if os(Windows)
// FIXME: - add support for Windows when regex function available
#endif

#if os(Linux)
// FIXME: - add support for Linux when regex function available
#endif

#if os(macOS)
/*
 Netrc feature depends upon `NSTextCheckingResult.range(withName name: String) -> NSRange`,
 which is only available in macOS 10.13+ at this time.
 */
@available (OSX 10.13, *)
/// Container of parsed netrc connection settings
public struct Netrc: AuthorizationProviding {
    /// Representation of `machine` connection settings & `default` connection settings.
    /// If `default` connection settings present, they will be last element.
    public let machines: [Machine]
    
    private init(machines: [Machine]) {
        self.machines = machines
    }
    
    /// Basic authorization header string
    /// - Parameter url: URI of network resource to be accessed
    /// - Returns: (optional) Basic Authorization header string to be added to the request
    public func authorization(for url: Foundation.URL) -> String? {
        guard let index = machines.firstIndex(where: { $0.name == url.host }) ?? machines.firstIndex(where: { $0.isDefault }) else { return nil }
        let machine = machines[index]
        let authString = "\(machine.login):\(machine.password)"
        guard let authData = authString.data(using: .utf8) else { return nil }
        return "Basic \(authData.base64EncodedString())"
    }
    
    /// Reads file at path or default location, and returns parsed Netrc representation
    /// - Parameter fileURL: Location of netrc file, defaults to `~/.netrc`
    /// - Returns: `Netrc` container with parsed connection settings, or error
    public static func load(fromFileAtPath filePath: AbsolutePath? = nil) -> Result<Netrc, Netrc.Error> {
        let filePath = filePath ?? AbsolutePath("\(NSHomeDirectory())/.netrc")
        
        guard FileManager.default.fileExists(atPath: filePath.pathString) else { return .failure(.fileNotFound(filePath)) }
        guard FileManager.default.isReadableFile(atPath: filePath.pathString),
              let fileContents = try? String(contentsOf: filePath.asURL, encoding: .utf8) else { return .failure(.unreadableFile(filePath)) }
        
        return Netrc.from(fileContents)
    }
    
    /// Regex matching logic for deriving `Netrc` container from string content
    /// - Parameter content: String text of netrc file
    /// - Returns: `Netrc` container with parsed connection settings, or error
    public static func from(_ content: String) -> Result<Netrc, Netrc.Error> {
        let content = trimComments(from: content)
        let regex = try! NSRegularExpression(pattern: RegexUtil.netrcPattern, options: [])
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..<content.endIndex, in: content))
        
        let machines: [Machine] = matches.compactMap {
            return Machine(for: $0, string: content, variant: "lp") ??
                Machine(for: $0, string: content, variant: "pl")
        }
        
        if let defIndex = machines.firstIndex(where: { $0.isDefault }) {
            guard defIndex == machines.index(before: machines.endIndex) else { return .failure(.invalidDefaultMachinePosition) }
        }
        guard machines.count > 0 else { return .failure(.machineNotFound) }
        return .success(Netrc(machines: machines))
    }
    /// Utility method to trim comments from netrc content
    /// - Parameter text: String text of netrc file
    /// - Returns: String text of netrc file *sans* comments
    private static func trimComments(from text: String) -> String {
        let regex = try! NSRegularExpression(pattern: RegexUtil.comments, options: .anchorsMatchLines)
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, range: range)
        var trimmedCommentsText = text
        matches.forEach {
            trimmedCommentsText = trimmedCommentsText
                .replacingOccurrences(of: nsString.substring(with: $0.range), with: "")
        }
        return trimmedCommentsText
    }
}

@available (OSX 10.13, *)
public extension Netrc {
    enum Error: Swift.Error {
        case invalidFilePath
        case fileNotFound(AbsolutePath)
        case unreadableFile(AbsolutePath)
        case machineNotFound
        case invalidDefaultMachinePosition
    }
    
    /// Representation of connection settings
    /// - important: Default connection settings are stored in machine named `default`
    struct Machine: Equatable {
        public let name: String
        public let login: String
        public let password: String
        
        public var isDefault: Bool {
            return name == "default"
        }
        
        public init(name: String, login: String, password: String) {
            self.name = name
            self.login = login
            self.password = password
        }
        
        init?(for match: NSTextCheckingResult, string: String, variant: String = "") {
            guard let name = RegexUtil.Token.machine.capture(in: match, string: string) ?? RegexUtil.Token.default.capture(in: match, string: string),
                let login = RegexUtil.Token.login.capture(prefix: variant, in: match, string: string),
                let password = RegexUtil.Token.password.capture(prefix: variant, in: match, string: string) else {
                    return nil
            }
            self = Machine(name: name, login: login, password: password)
        }
    }
}

@available (OSX 10.13, *)
fileprivate enum RegexUtil {
    @frozen fileprivate enum Token: String, CaseIterable {
        case machine, login, password, account, macdef, `default`
        
        func capture(prefix: String = "", in match: NSTextCheckingResult, string: String) -> String? {
            guard let range = Range(match.range(withName: prefix + rawValue), in: string) else { return nil }
            return String(string[range])
        }
    }

    static let comments: String = "\\#[\\s\\S]*?.*$"
    static let `default`: String = #"(?:\s*(?<default>default))"#
    static let accountOptional: String = #"(?:\s*account\s+\S++)?"#
    static let loginPassword: String = #"\#(namedTrailingCapture("login", prefix: "lp"))\#(accountOptional)\#(namedTrailingCapture("password", prefix: "lp"))"#
    static let passwordLogin: String = #"\#(namedTrailingCapture("password", prefix: "pl"))\#(accountOptional)\#(namedTrailingCapture("login", prefix: "pl"))"#
    static let netrcPattern = #"(?:(?:(\#(namedTrailingCapture("machine"))|\#(namedMatch("default"))))(?:\#(loginPassword)|\#(passwordLogin)))"#
    
    static func namedMatch(_ string: String) -> String {
        return #"(?:\s*(?<\#(string)>\#(string)))"#
    }
    
    static func namedTrailingCapture(_ string: String, prefix: String = "") -> String {
        return #"\s*\#(string)\s+(?<\#(prefix + string)>\S++)"#
    }
}
#endif
