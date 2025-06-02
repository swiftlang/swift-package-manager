//
//  DotPIFSerializer.swift
//  SwiftPM
//
//  Created by Paulo Mattos on 2025-04-18.
//

import Basics
import Foundation
import protocol TSCBasic.OutputByteStream

import SwiftBuild

/// Serializes the specified PIF as a **Graphviz** directed graph.
///
/// * [DOT command line](https://graphviz.org/doc/info/command.html)
/// * [DOT language specs](https://graphviz.org/doc/info/lang.html)
func writePIF(_ workspace: PIF.Workspace, toDOT outputStream: OutputByteStream) {
    var graph = DotPIFSerializer()

    graph.node(
        id: workspace.id,
        label: """
            <workspace>
            \(workspace.id)
            """,
        shape: "box3d",
        color: .black,
        fontsize: 7
    )

    for project in workspace.projects.map(\.underlying) {
        graph.edge(from: workspace.id, to: project.id, color: .lightskyblue)
        graph.node(
            id: project.id,
            label: """
                <project>
                \(project.id)
                """,
            shape: "box3d",
            color: .gray56,
            fontsize: 7
        )

        for target in project.targets {
            graph.edge(from: project.id, to: target.id, color: .lightskyblue)

            switch target {
            case .target(let target):
                graph.node(
                    id: target.id,
                    label: """
                        <target>
                        \(target.id)
                        name: \(target.name)
                        product type: \(target.productType)
                        \(target.buildPhases.summary)
                        """,
                    shape: "box",
                    color: .gray88,
                    fontsize: 5
                )

            case .aggregate:
                graph.node(
                    id: target.id,
                    label: """
                        <aggregate target>
                        \(target.id)
                        """,
                    shape: "folder",
                    color: .gray88,
                    fontsize: 5,
                    style: "bold"
                )
            }

            for targetDependency in target.common.dependencies {
                let linked = target.isLinkedAgainst(dependencyId: targetDependency.targetId)
                graph.edge(from: target.id, to: targetDependency.targetId, color: .gray40, style: linked ? "filled" : "dotted")
            }
        }
    }

    graph.write(to: outputStream)
}

fileprivate struct DotPIFSerializer {
    private var objects: [String] = []

    mutating func write(to outputStream: OutputByteStream) {
        func write(_ object: String) { outputStream.write("\(object)\n") }

        write("digraph PIF {")
        write("  dpi=400;") // i.e., MacBook Pro 16" is 226 pixels per inch (3072 x 1920).
        for object in objects {
            write("  \(object);")
        }
        write("}")
    }

    mutating func node(
        id: PIF.GUID,
        label: String? = nil,
        shape: String? = nil,
        color: Color? = nil,
        fontname: String? = "SF Mono Light",
        fontsize: Int? = nil,
        style: String? = nil,
        margin: Int? = nil
    ) {
        var attributes: [String] = []

        if let label { attributes.append("label=\(label.quote)") }
        if let shape { attributes.append("shape=\(shape)") }
        if let color { attributes.append("color=\(color)") }

        if let fontname { attributes.append("fontname=\(fontname.quote)") }
        if let fontsize { attributes.append("fontsize=\(fontsize)") }

        if let style { attributes.append("style=\(style)") }
        if let margin { attributes.append("margin=\(margin)") }

        var node = "\(id.quote)"
        if !attributes.isEmpty {
            let attributesList = attributes.joined(separator: ", ")
            node += " [\(attributesList)]"
        }
        objects.append(node)
    }

    mutating func edge(
        from left: PIF.GUID,
        to right: PIF.GUID,
        color: Color? = nil,
        style: String? = nil
    ) {
        var attributes: [String] = []

        if let color { attributes.append("color=\(color)") }
        if let style { attributes.append("style=\(style)") }

        var edge = "\(left.quote) -> \(right.quote)"
        if !attributes.isEmpty {
            let attributesList = attributes.joined(separator: ", ")
            edge += " [\(attributesList)]"
        }
        objects.append(edge)
    }

    /// Graphviz  default color scheme is **X11**:
    /// * https://graphviz.org/doc/info/colors.html
    enum Color: String {
        case black
        case gray
        case gray40
        case gray56
        case gray88
        case lightskyblue
    }
}

// MARK: - Helpers

fileprivate extension ProjectModel.BaseTarget {
    func isLinkedAgainst(dependencyId: ProjectModel.GUID) -> Bool {
        for buildPhase in self.common.buildPhases {
            switch buildPhase {
            case .frameworks(let frameworksPhase):
                for buildFile in frameworksPhase.files {
                    switch buildFile.ref {
                    case .reference(let id):
                        if dependencyId == id { return true }
                    case .targetProduct(let id):
                        if dependencyId == id { return true }
                    }
                }

            case .sources, .shellScript, .headers, .copyFiles, .copyBundleResources:
                break
            }
        }
        return false
    }
}

fileprivate extension [ProjectModel.BuildPhase] {
    var summary: String {
        var phases: [String] = []

        for buildPhase in self {
            switch buildPhase {
            case .sources(let sourcesPhase):
                var sources = "sources: "
                if sourcesPhase.files.count == 1 {
                    sources += "1 source file"
                } else {
                    sources += "\(sourcesPhase.files.count) source files"
                }
                phases.append(sources)

            case .frameworks(let frameworksPhase):
                var frameworks = "frameworks: "
                if frameworksPhase.files.count == 1 {
                    frameworks += "1 linked target"
                } else {
                    frameworks += "\(frameworksPhase.files.count) linked targets"
                }
                phases.append(frameworks)

            case .shellScript:
                phases.append("shellScript: 1 shell script")

            case .headers, .copyFiles, .copyBundleResources:
                break
            }
        }

        guard !phases.isEmpty else { return "" }
        return phases.joined(separator: "\n")
    }
}

fileprivate extension PIF.GUID {
    var quote: String {
        self.value.quote
    }
}

fileprivate extension String {
    /// Quote the name and escape the quotes and backslashes.
    var quote: String {
        "\"" + self
            .replacing("\"", with: "\\\"")
            .replacing("\\", with: "\\\\")
            .replacing("\n", with: "\\n") +
        "\""
    }
}
