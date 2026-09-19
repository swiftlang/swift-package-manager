import MyLib

@main
struct MyTransitiveApp {
    static func main() {
        print("MyTransitiveApp using MyLib \(myLibExperimentalName())")
    }
}
