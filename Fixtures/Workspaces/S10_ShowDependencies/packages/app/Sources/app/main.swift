import LibA
import SomeLib

@main
struct AppMain {
    static func main() {
        print("app says: \(LibA.greeting()) / \(SomeLib.greeting())")
    }
}
