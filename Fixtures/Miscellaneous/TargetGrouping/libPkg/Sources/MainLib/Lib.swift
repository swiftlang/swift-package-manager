import Core

public func publicFunc() -> Int {
    print("public decl")
    return PublicCore(publicVar: 10).publicVar
}
