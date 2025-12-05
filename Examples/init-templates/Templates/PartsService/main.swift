import ArgumentParser
import Foundation
import SystemPackage

enum fs {
    static var shared: FileManager { FileManager.default }
}

extension FileManager {
    func rm(atPath path: FilePath) throws {
        try self.removeItem(atPath: path.string)
    }
}

extension FilePath {
    static func / (left: FilePath, right: String) -> FilePath {
        left.appending(right)
    }
}

extension String {
    func write(toFile: FilePath) throws {
        // Create the directory if it doesn't yet exist
        try? fs.shared.createDirectory(atPath: toFile.removingLastComponent().string, withIntermediateDirectories: true)

        try self.write(toFile: toFile.string, atomically: true, encoding: .utf8)
    }

    func append(toFile file: FilePath) throws {
        let data = self.data(using: .utf8)
        try data?.append(toFile: file)
    }

    func indenting(_ level: Int) -> String {
        self.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n" + String(
            repeating: "    ",
            count: level
        ))
    }
}

extension Data {
    func append(toFile file: FilePath) throws {
        if let fileHandle = FileHandle(forWritingAtPath: file.string) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: URL(fileURLWithPath: file.string))
        }
    }
}

enum Database: String, ExpressibleByArgument, CaseIterable {
    case sqlite3, postgresql

    var packageDep: String {
        switch self {
        case .sqlite3:
            ".package(url: \"https://github.com/vapor/fluent-sqlite-driver.git\", from: \"4.0.0\"),"
        case .postgresql:
            ".package(url: \"https://github.com/vapor/fluent-postgres-driver.git\", from: \"2.10.1\"),"
        }
    }

    var targetDep: String {
        switch self {
        case .sqlite3:
            ".product(name: \"FluentSQLiteDriver\", package: \"fluent-sqlite-driver\"),"
        case .postgresql:
            ".product(name: \"FluentPostgresDriver\", package: \"fluent-postgres-driver\"),"
        }
    }

    var taskListItem: String {
        switch self {
        case .sqlite3:
            "[x] - Create SQLite3 DB (`Scripts/create-db.sh`)"
        case .postgresql:
            "[x] - Create PostgreSQL DB (`Scripts/create-db.sh`)"
        }
    }

    var appServerUse: String {
        switch self {
        case .sqlite3:
            """
            // add sqlite database
            fluent.databases.use(.sqlite(.file("part.sqlite")), as: .sqlite)
            """
        case .postgresql:
            """
            // add PostgreSQL database
            app.databases.use(
                .postgres(
                    configuration: .init(
                        hostname: "localhost",
                        username: "vapor",
                        password: "vapor",
                        database: "part",
                        tls: .disable
                    )
                ),
                as: .psql
            )
            """
        }
    }

    var commandLineCreate: String {
        switch self {
        case .sqlite3:
            "sqlite3 part.sqlite \"create table part (id VARCHAR PRIMARY KEY,description VARCHAR);\""
        case .postgresql:
            """
            createdb part
            # TODO complete the rest of the command-line script for PostgreSQL table/user creation
            """
        }
    }
}

func packageSwift(db: Database, name: String) -> String {
    """
    // swift-tools-version: 6.1

    import PackageDescription

    let package = Package(
        name: "part-service",
        platforms: [
            .macOS(.v14),
        ],
        dependencies: [
            .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
            .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
            .package(url: "https://github.com/hummingbird-project/hummingbird-fluent.git", from: "2.0.0"),
            \(db.packageDep.indenting(2))
        ],
        targets: [
            .target(
                name: "Models",
                dependencies: [
                    \(db.targetDep.indenting(3))
                ]
            ),
            .executableTarget(
                name: "\(name)",
                dependencies: [
                    .target(name: "Models"),
                    .product(name: "ArgumentParser", package: "swift-argument-parser"),
                    .product(name: "Hummingbird", package: "hummingbird"),
                    .product(name: "HummingbirdFluent", package: "hummingbird-fluent"),
                    \(db.targetDep.indenting(3))
                ]
            ),
        ]
    )
    """
}

func genReadme(db: Database) -> String {
    """
    # Parts Management

    Manage your parts using the power of Swift, Hummingbird, and Fluent!

    \(db.taskListItem)
    [x] - Add a Hummingbird app server, router, and endpoint for parts (`Sources/App/main.swift`)
    [x] - Create a model for part (`Sources/Models/Part.swift`)

    ## Getting Started

    Create the part database if you haven't already done so.

    ```
    ./Scripts/create-db.sh
    ```

    Start the application.

    ```
    swift run
    ```

    Curl the parts endpoint to see the list of parts:

    ```
    curl http://127.0.0.1:8080/parts
    ```
    """
}

func appServer(db: Database, migration: Bool) -> String {
    """
    import ArgumentParser
    import Hummingbird
    \(db == .sqlite3 ?
        "import FluentSQLiteDriver" :
        "import FluentPostgresDriver"
    )
    import HummingbirdFluent
    import Models

    \(migration ?
        """
        // An example migration.
        struct CreatePartMigration: Migration {
            func prepare(on database: Database) -> EventLoopFuture<Void> {
                fatalError("Implement part migration prepare")
            }

            func revert(on database: Database) -> EventLoopFuture<Void> {
                fatalError("Implement part migration revert")
            }
        }
        """ : ""
    )

    @main
    struct PartServiceGenerator: AsyncParsableCommand {
        \(migration ? "@Flag var migrate: Bool = false" : "")
        mutating func run() async throws {
            var logger = Logger(label: "PartService")
            logger.logLevel = .debug
            let fluent = Fluent(logger: logger)

            \(db.appServerUse)

            \(migration ?
        """
        await fluent.migrations.add(CreatePartMigration())

        // migrate
        if self.migrate {
            try await fluent.migrate()
        }
        """.indenting(2) : ""
    )

            // create router and add a single GET /parts route
            let router = Router()
            router.get("parts") { request, _ -> [Part] in
                return try await Part.query(on: fluent.db()).all()
            }

            // create application using router
            let app = Application(
                router: router,
                configuration: .init(address: .hostname("127.0.0.1", port: 8080))
            )

            // run hummingbird application
            try await app.runService()
        }
    }
            """
}

func partModel(db: Database) -> String {
    """
    \(db == .sqlite3 ?
        "import FluentSQLiteDriver" :
        "import FluentPostgresDriver"
    )

    public final class Part: Model, @unchecked Sendable {
        // Name of the table or collection.
        public static let schema = "part"

        // Unique identifier for this Part.
        @ID(key: .id)
        public var id: UUID?

        // The Part's description.
        @Field(key: "description")
        public var description: String

        // Creates a new, empty Part.
        public init() { }

        // Creates a new Part with all properties set.
        public init(id: UUID? = nil, description: String) {
            self.id = id
            self.description = description
        }
    }
    """
}

func createDbScript(db: Database) -> String {
    """
    #!/bin/bash

    \(db.commandLineCreate)
    """
}

@main
struct PartServiceGenerator: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "This template gets you started with a service to track your parts with app server and database."
    )

    @Option(help: .init(visibility: .hidden))
    var pkgDir: String?

    @Flag(help: "Add a README.md file with and introduction and tour of the code")
    var readme: Bool = false

    @Option(help: "Pick a database system for part storage and retrieval.")
    var database: Database = .sqlite3

    @Flag(help: "Add a starting database  migration routine.")
    var migration: Bool = false

    @Option(help: .init(visibility: .hidden))
    var name: String = "App"

    mutating func run() throws {
        guard let pkgDir = self.pkgDir else {
            fatalError("No --pkg-dir was provided.")
        }
        guard case let pkgDir = FilePath(pkgDir) else { fatalError() }

        print(pkgDir.string)

        // Remove the main.swift left over from the base executable template, if it exists
        try? fs.shared.rm(atPath: pkgDir / "Sources/main.swift")

        // Start from scratch with the Package.swift
        try? fs.shared.rm(atPath: pkgDir / "Package.swift")

        try packageSwift(db: self.database, name: self.name).write(toFile: pkgDir / "Package.swift")
        if self.readme {
            try genReadme(db: self.database).write(toFile: pkgDir / "README.md")
        }

        try? fs.shared.rm(atPath: pkgDir / "Sources/\(self.name)")
        try appServer(db: self.database, migration: self.migration)
            .write(toFile: pkgDir / "Sources/\(self.name)/main.swift")
        try partModel(db: self.database).write(toFile: pkgDir / "Sources/Models/Part.swift")

        let script = pkgDir / "Scripts/create-db.sh"
        try createDbScript(db: self.database).write(toFile: script)
        try fs.shared.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.string)

        if self.database == .sqlite3 {
            try "\npart.sqlite".append(toFile: pkgDir / ".gitignore")
        }
    }
}
