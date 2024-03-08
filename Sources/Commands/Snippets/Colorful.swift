//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public protocol Colorful: CustomStringConvertible {
    func terminalString() -> String
}

extension Colorful {
    public var description: String {
        return terminalString()
    }
}

extension Colorful where Self: RawRepresentable, RawValue: StringProtocol {
    func terminalString() -> String {
        return String(self.rawValue)
    }
}

extension String: Colorful {
    public func terminalString() -> String {
        return self
    }
}

extension Substring: Colorful {
    public func terminalString() -> String {
        return String(self)
    }
}

extension Array: Colorful where Element == Colorful {
    public func terminalString() -> String {
        return self.map { $0.terminalString() }.joined()
    }
}

extension Optional: CustomStringConvertible where Wrapped: Colorful {
    public var description: String {
        return terminalString()
    }
}

extension Optional: Colorful where Wrapped: Colorful {
    public func terminalString() -> String {
        if let unwrapped = self {
            return unwrapped.terminalString()
        } else {
            return ""
        }
    }
}

@resultBuilder
package struct ColorBuilder {
    package static func buildOptional(_ component: [Colorful]?) -> [Colorful] {
        return component ?? []
    }

    package static func buildBlock(_ components: Colorful...) -> [Colorful] {
        return components
    }

    package static func buildEither(first component: [Colorful]) -> [Colorful] {
        return component
    }

    package static func buildEither(second component: [Colorful]) -> [Colorful] {
        return component
    }
}

protocol Color: Colorful {}

enum Color4: String, Color {
    case black = "\u{001b}[30m"
    case red = "\u{001b}[31m"
    case green = "\u{001b}[32m"
    case yellow = "\u{001b}[33m"
    case blue = "\u{001b}[34m"
    case magenta = "\u{001b}[35m"
    case cyan = "\u{001b}[36m"
    case white = "\u{001b}[37m"

    case brightBlack = "\u{001b}[30;1m"
    case brightRed = "\u{001b}[31;1m"
    case brightGreen = "\u{001b}[32;1m"
    case brightYellow = "\u{001b}[33;1m"
    case brightBlue = "\u{001b}[34;1m"
    case brightMagenta = "\u{001b}[35;1m"
    case brightCyan = "\u{001b}[36;1m"
    case brightWhite = "\u{001b}[37;1m"

    case reset = "\u{001b}[0m"

    var bright: Color4 {
        switch self {
        case .black:
            return .brightBlack
        case .red:
            return .brightRed
        case .green:
            return .brightGreen
        case .yellow :
            return .brightYellow
        case .blue:
            return .brightBlue
        case .magenta:
            return .brightMagenta
        case .cyan:
            return .brightCyan
        case .white:
            return .brightWhite
        default:
            return self
        }
    }

    var description: String {
        return self.rawValue
    }
}

package func colorized(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.reset, builder)
}

package func plain(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.reset, builder)
}

package func black(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.black, builder)
}

package func brightBlack(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightBlack, builder)
}

package func red(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.red, builder)
}

package func brightRed(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightRed, builder)
}

package func green(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.green, builder)
}

package func brightGreen(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightGreen, builder)
}

package func yellow(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.yellow, builder)
}

package func brightYellow(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightYellow, builder)
}

package func blue(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.blue, builder)
}

package func brightBlue(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightBlue, builder)
}

package func magenta(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.magenta, builder)
}

package func brightMagenta(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightMagenta, builder)
}

package func cyan(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.cyan, builder)
}

package func brightCyan(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightCyan, builder)
}

package func white(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.white, builder)
}

package func brightWhite(@ColorBuilder builder: () -> [Colorful]) -> Colorful {
    return Colorized(.brightWhite, builder)
}

struct Colorized: Colorful {
    var color: Color
    var items: [Colorful]

    init(_ color: Color = Color4.reset, _ items: [Colorful]) {
        self.color = color
        self.items = items
    }

    init(_ color: Color4 = .reset, @ColorBuilder _ builder: () -> [Colorful]) {
        self.color = color
        self.items = builder()
    }

    func terminalString() -> String {
        let inner = items.map { $0.terminalString() }.joined()
        guard inner.hasSuffix(Color4.reset.rawValue) else {
            return color.terminalString() + inner + Color4.reset.rawValue
        }
        return color.terminalString() + inner
    }
}
