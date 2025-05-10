
public extension Collection {
    func shuffle() -> [Iterator.Element] {
        var array = Array(self)
        array.shuffleInPlace()

        return array
    }
}

public extension MutableCollection {
    /// Shuffles the contents of this collection.
    mutating func shuffleInPlace() {
        let c = count
        guard c > 1 else { return }
        
        for (firstUnshuffled, unshuffledCount) in zip(indices, stride(from: c, to: 1, by: -1)) {
            var g = SystemRandomNumberGenerator()
            let d = Int.random(in: 1...unshuffledCount, using: &g)
            let i = index(firstUnshuffled, offsetBy: d)
            swapAt(firstUnshuffled, i)
        }
    }
}


public let shuffle = false
