public enum Rank : Int {
    case Ace = 1
    case Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten
    case Jack, Queen, King
}

// MARK: - Comparable

extension Rank : Comparable {}

public func <(lhs: Rank, rhs: Rank) -> Bool {
    switch (lhs, rhs) {
    case (_, _) where lhs == rhs:
        return false
    case (.Ace, _):
        return false
    default:
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - CustomStringConvertible

extension Rank : CustomStringConvertible {
    public var description: String {
        switch self {
        case .Ace: return "A"
        case .Jack: return "J"
        case .Queen: return "Q"
        case .King: return "K"
        default:
            return "\(rawValue)"
        }
    }
}
