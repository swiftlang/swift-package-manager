@main
public struct MyExec {
    public private(set) var text = "Hello, World!"

    public static func main() {
        print(MyExec().text)
    }
}
