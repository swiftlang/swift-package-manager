import XCTest

import Basic
import SPMUtility

class FSWatchTests: XCTestCase {

    func testBasics() throws {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { path in
            // Construct the paths that we need to watch.
            let pathsToWatch = [
                path.appending(component: "foo"),
                path.appending(component: "bar"),
            ]

            // Create the paths.
            for path in pathsToWatch {
                try localFileSystem.createDirectory(path)
            }

            let condition = Condition()
            let delegate = Delegate(condition)

            let watcher = FSWatch(paths: pathsToWatch, delegate: delegate)
            try watcher.start()

            for file in ["a", "b", "c"] {
                let filePath = path.appending(components: "foo", file)
                try localFileSystem.writeFileContents(filePath, bytes: "")
            }

            condition.whileLocked {
                condition.wait()
            }

            XCTAssertFalse(delegate.receivedEvents.isEmpty)
        }
    }
}

class Delegate: FSWatchDelegate {
    var receivedEvents: [AbsolutePath] = []

    let condition: Condition

    init(_ condition: Condition) {
        self.condition = condition
    }

    func pathsDidReceiveEvent(_ paths: [AbsolutePath]) {
        receivedEvents += paths

        print(paths)

        condition.whileLocked {
            condition.signal()
        }
    }
}
