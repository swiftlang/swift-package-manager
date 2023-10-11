@main
struct AsyncMain4 {
  static func main() async {
    print(getGreeting4())
  }

  static func getGreeting4() -> String {
      return "Hello, async universe"
  }
}
