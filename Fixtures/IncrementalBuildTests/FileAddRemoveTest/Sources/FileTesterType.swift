protocol FileTesterType {
    static var fileTester: String {get}
    static var fileTesterToo: String {get}
}
extension FileTesterType {
    static var fileTesterToo: String { return Self.fileTester }
}
