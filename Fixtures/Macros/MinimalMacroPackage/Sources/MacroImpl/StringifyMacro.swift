import Foundation

#if SHOULD_NOT_BE_SET
#error("SHOULD_NOT_BE_SET was passed to macro compilation, but should only affect the target build.")
#endif

@main
struct MacroPlugin {
    static func main() throws {
        while true {
            guard let headerData = try read(count: 8),
                  headerData.count == 8 else {
                break
            }
            let length = headerData.withUnsafeBytes { buffer in
                buffer.load(as: UInt64.self)
            }
            let payloadLength = UInt64(littleEndian: length)

            if payloadLength == 0 {
                break
            }

            guard let payloadData = try read(count: Int(payloadLength)),
                  payloadData.count == Int(payloadLength) else {
                break
            }

            guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }

            if json.keys.contains("getCapability") {
                let response: [String: Any] = [
                    "getCapabilityResult": [
                        "capability": [
                            "protocolVersion": 2
                        ]
                    ]
                ]
                if let responseData = try? JSONSerialization.data(withJSONObject: response) {
                    try writeMessage(responseData, to: FileHandle.standardOutput)
                }
            } else if json.keys.contains("expandFreestandingMacro") {
                #if USE_CUSTOM_EXPANSION
                let expandedSource = "\"custom_expanded\""
                #else
                let expandedSource = "\"expanded\""
                #endif
                let response: [String: Any] = [
                    "expandMacroResult": [
                        "expandedSource": expandedSource,
                        "diagnostics": []
                    ]
                ]
                if let responseData = try? JSONSerialization.data(withJSONObject: response) {
                    try writeMessage(responseData, to: FileHandle.standardOutput)
                }
            }
        }
    }
}

private func read(count: Int) throws -> Data? {
    var accumulated = Data()
    while accumulated.count < count {
        let remaining = count - accumulated.count
        guard let chunk = try FileHandle.standardInput.read(upToCount: remaining), !chunk.isEmpty else {
            return accumulated.isEmpty ? nil : accumulated
        }
        accumulated.append(chunk)
    }
    return accumulated
}

private func writeMessage(_ data: Data, to handle: FileHandle) throws {
    var length = UInt64(data.count).littleEndian
    let headerData = withUnsafeBytes(of: &length) { buffer in
        Data(buffer)
    }
    try handle.write(contentsOf: headerData)
    try handle.write(contentsOf: data)
}
