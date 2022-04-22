import Foundation

@main
public struct PluginGeneratedResources {
    public private(set) var text = "Hello, World!"

    public static func main() {
        let path = Bundle.module.path(forResource: "best", ofType: "txt")
        let exists = FileManager.default.fileExists(atPath: path!)
        assert(exists, "generated file is missing")
        print(PluginGeneratedResources().text)
    }
}
