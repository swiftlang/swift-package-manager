import FooModule
import BarModule


@main
public class App {
    public static func main() {
        let result = describeServices()
        print(result)
    }

    /// Builds one service from each dependency and reports what each one sees of Alamofire.
    /// Each dependency compiles against its own Alamofire major, so the output should differ.
    public static func describeServices() -> String {
        let foo = FooService(name: "foo", id: 1)
        let bar = BarService(name: "bar")
        return """
        foo: type=\(foo.alamofireTypeName()) accept-encoding=\(foo.acceptEncoding() ?? "nil")
        bar: type=\(bar.alamofireTypeName()) accept-encoding=\(bar.acceptEncoding() ?? "nil")
        """
    }
}
