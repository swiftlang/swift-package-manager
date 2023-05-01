import DataManager

public struct PublicCore {
    public let publicVar: Int
    public init(publicVar: Int) {
        self.publicVar = publicVar
    }
    public func publicCoreFunc() {
        managePublicFunc()
    }
}
