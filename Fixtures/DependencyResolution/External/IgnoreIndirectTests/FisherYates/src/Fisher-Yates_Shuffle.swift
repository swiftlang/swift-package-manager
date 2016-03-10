#if os(OSX) || os(iOS)
import Darwin
#else
import Glibc
#endif

public extension Collection {
    func shuffle() -> [Iterator.Element] {
        var array = Array(self)
        array.shuffleInPlace()

        return array
    }
}

public extension MutableCollection where Index == Int {
    mutating func shuffleInPlace() {
        guard count > 1 else { return }

        for i in 0..<count - 1 {
#if os(OSX) || os(iOS)
            let j = Int(arc4random_uniform(UInt32(count - i))) + i
#else
            let j = Int(random() % (count - i)) + i
#endif
            guard i != j else { continue }
            swap(&self[i], &self[j])
        }
    }
}

public let shuffle = false
