protocol FileTestType {
    static var fileTester: String {get}
    static var fileTesterToo: String {get}
}
extension FileTestType {
    static var fileTesterToo: String { return Self.fileTester }
}
