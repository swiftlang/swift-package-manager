import Foundation

@objc public class Widget: NSObject {
    @objc public let value: Int

    @objc public init(value: Int) {
        self.value = value
        super.init()
    }
}
