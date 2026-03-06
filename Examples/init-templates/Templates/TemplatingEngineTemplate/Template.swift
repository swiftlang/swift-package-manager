import ArgumentParser
import Foundation
import PathKit
import Stencil

//This is an example of a template that uses the Stencil library templates to generate files.
@main
struct TemplateDeclarative: ParsableCommand {
    enum Template: String, ExpressibleByArgument, CaseIterable {
        case EnumExtension
        case StructColors
        case StaticColorSets

        var path: String {
            switch self {
            case .EnumExtension:
                "EnumExtension.stencil"
            case .StructColors:
                "StructColors.stencil"
            case .StaticColorSets:
                "StaticColorSets.stencil"
            }
        }

        var name: String {
            switch self {
            case .EnumExtension:
                "EnumExtension"
            case .StructColors:
                "StructColors"
            case .StaticColorSets:
                "StaticColorSets"
            }
        }
    }

    // The template uses the Swift argument parser to expose arguments to template generator.
    @Option(
        name: [.customLong("template")],
        help: "Choose one template: \(Template.allCases.map(\.rawValue).joined(separator: ", "))"
    )
    var template: Template

    @Option(name: [.customLong("enumName"), .long], help: "Name of the generated enum")
    var enumName: String = "AppColors"

    @Flag(name: .shortAndLong, help: "Use public access modifier")
    var publicAccess: Bool = false

    @Option(
        name: [.customLong("palette"), .long],
        parsing: .upToNextOption,
        help: "Palette name of the format PaletteName:name=#RRGGBBAA"
    )
    var palettes: [String]

    var templatesDirectory = "./MustacheTemplates"

    func run() throws {
        let parsedPalettes: [[String: Any]] = try palettes.map { paletteString in
            let parts = paletteString.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                throw ValidationError("Each --palette must be in the format PaletteName:name=#RRGGBBAA,...")
            }

            let paletteName = String(parts[0])
            let colorEntries = parts[1].split(separator: ",")

            let colors = try colorEntries.map { entry in
                let colorParts = entry.split(separator: "=")
                guard colorParts.count == 2 else {
                    throw ValidationError("Color entry must be in format name=#RRGGBBAA")
                }

                let name = String(colorParts[0])
                let hex = colorParts[1].trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                guard hex.count == 8 else {
                    throw ValidationError("Hex must be 8 characters (RRGGBBAA)")
                }

                return [
                    "name": name,
                    "red": String(hex.prefix(2)),
                    "green": String(hex.dropFirst(2).prefix(2)),
                    "blue": String(hex.dropFirst(4).prefix(2)),
                    "alpha": String(hex.dropFirst(6)),
                ]
            }

            return [
                "name": paletteName,
                "colors": colors,
            ]
        }

        let context: [String: Any] = [
            "enumName": enumName,
            "publicAccess": publicAccess,

            "palettes": parsedPalettes,
        ]

        if let url = Bundle.module.url(forResource: "\(template.name)", withExtension: "stencil") {
            print("Template URL: \(url)")

            let path = url.deletingLastPathComponent()
            let environment = Environment(loader: FileSystemLoader(paths: [Path(path.path)]))

            let rendered = try environment.renderTemplate(name: "\(self.template.path)", context: context)

            print(rendered)
            try rendered.write(toFile: "User.swift", atomically: true, encoding: .utf8)

        } else {
            print("Template not found.")
        }
    }
}
