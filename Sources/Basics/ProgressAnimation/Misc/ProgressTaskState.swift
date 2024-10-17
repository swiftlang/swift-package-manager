//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// FIXME: maybe split state and event
package enum ProgressTaskState {
    case discovered
    // FIXME: running state needs %progress for download style tasks
    case started
    case completed(ProgressTaskCompletion)
}

extension ProgressTaskState {
    var visualColor: ANSITextStyle.Color {
        switch self {
        case .discovered: .yellow
        case .started: .cyan
        case .completed(.succeeded): .green
        case .completed(.failed): .red
        case .completed(.cancelled): .magenta
        case .completed(.skipped): .blue
        }
    }

    var visualSymbol: String {
        #if os(macOS)
        switch self {
        case .discovered: "􀊗 "
        case .started: "􀊕 "
        case .completed(.succeeded): "􀁢 "
        case .completed(.failed): "􀁠 "
        case .completed(.cancelled): "􀜪 "
        case .completed(.skipped): "􀺅 "
        }
        #else
        switch self {
        case .discovered: "⏸"
        case .started: "▶"
        case .completed(.succeeded): "✔"
        case .completed(.failed): "✘"
        case .completed(.cancelled): "⏹"
        case .completed(.skipped): "⏭ "
        }
        #endif
    }
}

extension ProgressTaskState: Equatable {}

extension ProgressTaskState: Hashable {}
