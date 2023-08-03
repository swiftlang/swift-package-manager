import Foundation

@main
struct Exec {
  static func main() throws {
      let config = InstalledSwiftPMConfiguration(version: 1, swiftSyntaxVersionForMacroTemplate: .init(major: 509, minor: 0, patch: 0))
      let data = try JSONEncoder().encode(config)
      try data.write(to: URL(fileURLWithPath: "config.json"))
  }
}
