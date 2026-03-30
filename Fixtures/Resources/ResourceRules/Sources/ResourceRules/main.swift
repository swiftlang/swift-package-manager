import Foundation
import AppKit

@main
struct Entry {
    public static func main() {
        guard Bundle.module.url(forResource: "CopiedAssets", withExtension: "xcassets") != nil else {
            print("Failed to lookup unprocessed asset catalog")
            return
        }
        guard Bundle.module.image(forResource: "processedpixel") != nil else {
            print("Failed to lookup processed asset from catalog")
            return
        }
        print("succeeded")
    }
}
