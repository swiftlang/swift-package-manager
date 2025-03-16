//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin.C
#elseif canImport(Android)
import Android
#endif

@main
struct Entrypoint {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--test-bundle-path" {
            let bundlePath = args[2]
            #if canImport(Darwin)
            let flags = RTLD_LAZY | RTLD_FIRST
            #else
            let flags = RTLD_LAZY
            #endif
            guard let image = dlopen(bundlePath, flags) else {
                let errorMessage: String = dlerror().flatMap {
                    String(validatingCString: $0)
                } ?? "An unknown error occurred."
                fatalError("Failed to open test bundle at path \(bundlePath): \(errorMessage)")
            }
            defer {
                dlclose(image)
            }

            // Find and call the main function from the image. This function may
            // link to the copy of Swift Testing included with Xcode, or may link to
            // a copy that's included as a package dependency.
            let main = dlsym(image, "main").map {
                unsafeBitCast(
                    $0,
                    to: (@convention(c) (CInt, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> CInt).self
                )
            }
            if let main {
                exit(main(CommandLine.argc, CommandLine.unsafeArgv))
            }
        }
    }
}
