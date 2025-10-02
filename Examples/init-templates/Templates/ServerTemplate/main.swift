import ArgumentParser
import SystemPackage
import Foundation

struct fs {
    static var shared: FileManager { FileManager.default }
}
extension FileManager {
    func rm(atPath path: FilePath) throws {
        try self.removeItem(atPath: path.string)
    }
    
    func csl(atPath linkPath: FilePath, pointTo relativeTarget: FilePath) throws {
        let linkURL = URL(fileURLWithPath: linkPath.string)
        let destinationURL = URL(fileURLWithPath: relativeTarget.string, relativeTo: linkURL.deletingLastPathComponent())
        try self.createSymbolicLink(at: linkURL, withDestinationURL: destinationURL)
    }
}

extension FilePath {
    static func / (left: FilePath, right: String) -> FilePath {
        left.appending(right)
    }

    func relative(to base: FilePath) -> FilePath {
        let targetURL = URL(fileURLWithPath: self.string)
        let baseURL = URL(fileURLWithPath: base.string, isDirectory: true)

        let relativeURL = targetURL.relativePath(from: baseURL)
        return FilePath(relativeURL)
    }
}

extension URL {
    /// Compute the relative path from one URL to another
    func relativePath(from base: URL) -> String {
        let targetComponents = self.standardized.pathComponents
        let baseComponents = base.standardized.pathComponents

        var index = 0
        while index < targetComponents.count &&
              index < baseComponents.count &&
              targetComponents[index] == baseComponents[index] {
            index += 1
        }

        let up = Array(repeating: "..", count: baseComponents.count - index)
        let down = targetComponents[index...]

        return (up + down).joined(separator: "/")
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
        self.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n" + String(repeating: "    ", count: level))
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

enum ServerType: String, ExpressibleByArgument, CaseIterable {
    case crud, bare
    
    var description: String {
        switch self {
        case .crud:
            return "CRUD"
        case .bare:
            return "Bare"
        }
    }

    //Package.swift manifest file writing
    var packageDep: String {
        switch self {
        case .crud:
            """
            // Server scaffolding
            .package(url: "https://github.com/vapor/vapor", from: "4.0.0"),
            .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.1.0"),
            .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
            .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
            .package(url: "https://github.com/swift-server/swift-openapi-vapor", from: "1.0.0"),
            
            // Telemetry
            .package(url: "https://github.com/apple/swift-log", .upToNextMajor(from: "1.5.2")),
            .package(url: "https://github.pie.apple.com/swift-server/swift-logback", from: "2.3.1"),
            .package(url: "https://github.com/apple/swift-metrics", from: "2.3.4"),
            .package(url: "https://github.com/swift-server/swift-prometheus", from: "2.1.0"),
            .package(url: "https://github.com/apple/swift-distributed-tracing", from: "1.2.0"),
            .package(url: "https://github.com/swift-otel/swift-otel", .upToNextMinor(from: "0.11.0")),
            
            // Database
            .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
            .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
            
            // HTTP client
            .package(url: "https://github.com/swift-server/async-http-client", from: "1.25.0"),
            
            """
        case .bare:
            """
            // Server
            .package(url: "https://github.com/vapor/vapor", from: "4.0.0"),
            """
        }
    }
    
    var targetName: String {
        switch self {
        case .bare:
            "BareHTTPServer"
        case .crud:
            "CRUDHTTPServer"

        }
    }
    
    var platform: String {
        switch self {
        case .bare:
            ".macOS(.v13)"
        case .crud:
            ".macOS(.v14)"
        }
    }

    var targetDep: String {
        switch self {
        case .crud:
            """
            // Server scaffolding
            .product(name: "Vapor", package: "vapor"),
            .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),

            // Telemetry
            .product(name: "Logging", package: "swift-log"),
            .product(name: "Logback", package: "swift-logback"),
            .product(name: "Metrics", package: "swift-metrics"),
            .product(name: "Prometheus", package: "swift-prometheus"),
            .product(name: "Tracing", package: "swift-distributed-tracing"),
            .product(name: "OTel", package: "swift-otel"),
            .product(name: "OTLPGRPC", package: "swift-otel"),

            // Database
            .product(name: "Fluent", package: "fluent"),
            .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),

            // HTTP client
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            """
        case .bare:
            """
            // Server
            .product(name: "Vapor", package: "vapor")
            """
        }
    }
    
    var plugin: String {
        switch self {
        case .bare:
            ""
        case .crud:
            """
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
            """
            
        }
    }
    
    
    //Readme items
    
    var features: String {
        switch self {
        case .bare:
            """
            - base server (Vapor)
            - a single `/health` endpoint
            - logging to stdout
            """
        case .crud:
            """
            - base server
            - OpenAPI-generated server stubs
            - Telemetry: logging to a file and stdout, metrics emitted over Prometheus, traces emitted over OTLP
            - PostgreSQL database
            - HTTP client for making upstream calls
            """

        }
    }
    
    var callingLocally : String {
        switch self {
        case .bare:
            """
            In another window, test the health check: `curl http://localhost:8080/health`.
            """
        case .crud:
            """
            ### Health check
            
            ```sh
            curl -f http://localhost:8080/health
            ```
            
            ### Create a TODO
            
            ```sh
            curl -X POST http://localhost:8080/api/todos --json '{"contents":"Smile more :)"}'
            {
              "contents" : "Smile more :)",
              "id" : "066E0A57-B67B-4C41-9DFF-99C738664EBD"
            }
            ```
            
            ### List TODOs
            
            ```sh
            curl -X GET http://localhost:8080/api/todos
            {
              "items" : [
                {
                  "contents" : "Smile more :)",
                  "id" : "066E0A57-B67B-4C41-9DFF-99C738664EBD"
                }
              ]
            }
            ```
            
            ### Get a single TODO
            
            ```sh
            curl -X GET http://localhost:8080/api/todos/066E0A57-B67B-4C41-9DFF-99C738664EBD
            {
              "contents" : "hello_again",
              "id" : "A8E02E7C-1451-4CF9-B5C5-A33E92417454"
            }
            ```
            
            ### Delete a TODO
            
            ```sh
            curl -X DELETE http://localhost:8080/api/todos/066E0A57-B67B-4C41-9DFF-99C738664EBD
            ```
            
            ### Triggering a synthetic crash
            
            For easier testing of crash log uploading behavior, this template server also includes an operation for intentionally
            crashing the server.
            
            > Warning: Consider removing this endpoint or guarding it with admin auth before deploying to production.
            
            ```sh
            curl -f -X POST http://localhost:8080/api/crash
            ```
            
            The JSON crash log then appears in the `/logs` directory in the container.
            
            ## Viewing the API docs
            
            Run: `open http://localhost:8080/openapi.html`, from where you can make test HTTP requests to the local server.
            
            ## Viewing telemetry
            
            Run (and leave running) `docker-compose -f Deploy/Local/docker-compose.yaml up`, and make a few test requests in a separate Terminal window.
            
            Afterwards, this is how you can view the emitted logs, metrics, and traces.
            
            ### Logs
            
            If running from `docker-compose`:
            
            ```sh
            docker exec local-crud-1 tail -f /tmp/crud_server.log
            ```
            
            If running in VS Code/Xcode, logs will be emitted in the IDE's console.
            
            ### Metrics
            
            Run:
            
            ```sh
            open http://localhost:9090/graph?g0.expr=http_requests_total&g0.tab=1&g0.display_mode=lines&g0.show_exemplars=0&g0.range_input=1h
            ```
            
            to see the `http_requests_total` metric counts.
            
            ### Traces
            
            Run:
            
            ```sh
            open http://localhost:16686/search?limit=20&lookback=1h&service=CRUDHTTPServer
            ```
            
            to see traces, which you can click on to reveal the individual spans with attributes.
            
            ## Configuration
            
            The service is configured using the following environment variables, all of which are optional with defaults.
            
            Some of these values are overriden in `docker-compose.yaml` for running locally, but if you're deploying in a production environment, you'd want to customize them further for easier operations.
            
            - `SERVER_ADDRESS` (default: `"0.0.0.0"`): The local address the server listens on.
            - `SERVER_PORT` (default: `8080`): The local post the server listens on.
            - `LOG_FORMAT` (default: `json`, possible values: `json`, `keyValue`): The output log format used for both file and console logging.
            - `LOG_FILE` (default: `/tmp/crud_server.log`): The file to write logs to.
            - `LOG_LEVEL` (default: `debug`, possible values: `trace`, `debug`, `info`, `notice`, `warning`, `error`): The level at which to log, includes all levels more severe as well.
            - `LOG_BUFFER_SIZE` (default: `1024`): The number of log events to keep in memory before discarding new events if the log handler can't write into the backing file/console fast enough.
            - `OTEL_EXPORTER_OTLP_ENDPOINT` (default: `localhost:4317`): The otel-collector URL.
            - `OTEL_EXPORTER_OTLP_INSECURE` (default: `false`): Whether to allow an insecure connection when no scheme is provided in `OTEL_EXPORTER_OTLP_ENDPOINT`.
            - `POSTGRES_URL` (default: `postgres://postgres@localhost:5432/postgres?sslmode=disable`): The URL to connect to the Postgres instance.
            - `POSTGRES_MTLS` (default: nil): Set to `1` in order to use mTLS for authenticating with Postgres.
            - `POSTGRES_MTLS_CERT_PATH` (default: nil): The path to the client certificate chain in a PEM file.
            - `POSTGRES_MTLS_KEY_PATH` (default: nil): The path to the client private key in a PEM file.
            - `POSTGRES_MTLS_ADDITIONAL_TRUST_ROOTS` (default: nil): One or more comma-separated paths to additional trust roots.
            """
        }
    }
        
    var deployToKube: String {
        switch self {
        case .crud:
            ""
        case .bare:
            
            """
            ## Deploying to Kube
                
            Check out [`Deploy/Kube`](Deploy/Kube) for instructions on deploying to Apple Kube.
                
            """
            
        }
        
    }
}

func packageSwift(serverType: ServerType) -> String {
    """
    // swift-tools-version: 6.1
    // The swift-tools-version declares the minimum version of Swift required to build this package.
    
    import PackageDescription
    
    let package = Package(
        name: "\(serverType.targetName.indenting(1))",
        platforms: [
            \(serverType.platform.indenting(2))
        ],
        dependencies: [
            \(serverType.packageDep.indenting(2))
        ],
        targets: [
            .executableTarget(
                name: "\(serverType.targetName.indenting(3))",
                dependencies: [
                    \(serverType.targetDep.indenting(4))
                ],
                path: "Sources",
                \(serverType.plugin.indenting(3))
                
            ),
        ]
    )
    """
}

func genRioTemplatePkl(serverType: ServerType) -> String {
    """
    /// For more information on how to configure this module, visit:
    \(serverType == .crud ?
    """
    /// https://pkl.apple.com/apple-package-docs/artifacts.apple.com/pkl/pkl/rio/1.3.3/Rio/index.html
    /// https://pkl.apple.com/apple-package-docs/artifacts.apple.com/pkl/pkl/rio/current/Rio/index.html#_overview
    """ :
    """
    /// <https://pkl.apple.com/apple-package-docs/rio/current/Rio/index.html#_overview>
    """
    )
    @ModuleInfo { minPklVersion = "0.24.0" }
    amends "package://artifacts.apple.com/pkl/pkl/rio@1.3.1#/Rio.pkl"

    // ---

    // !!! This is a template for your Rio file.
    // Fill in the variables below first, and then rename this file to `rio.pkl`.

    /// The docker.apple.com/OWNER part of the pushed docker image.
    local dockerOwnerName: String = "CHANGE_ME"

    /// The docker.apple.com/owner/REPO part of the pushed docker image.
    local dockerRepoName: String = "CHANGE_ME"

    // ---

    schemaVersion = "2.0"
    pipelines {
      new {
        group = "publish"
        branchRules {
          includePatterns {
            "main"
          }
        }
        machine {
          baseImage = "docker.apple.com/cpbuild/cp-build:latest"
        }
        build {
          template = "freestyle:v4:publish"
          steps {
            #"echo "noop""#
          }
        }
        package {
          version = "${GIT_BRANCH}-#{GIT_COMMIT}"
          dockerfile {
            new {
              dockerfilePath = "Dockerfile"
              perApplication = false
              publish {
                new {
                  repo = "docker.apple.com/\\(dockerOwnerName)/\\(dockerRepoName)"
                }
              }
            }
          }
        }
      }
      new {
        group = "build"
        branchRules {
          includePatterns {
            "main"
          }
        }
        machine {
          baseImage = "docker.apple.com/cpbuild/cp-build:latest"
        }
        build {
          template = "freestyle:v4:prb"
          steps {
            #"echo "noop""#
          }
        }
        package {
          version = "${GIT_BRANCH}-#{GIT_COMMIT}"
          dockerfile {
            new {
              dockerfilePath = "Dockerfile"
              perApplication = false
            }
          }
        }
      }
      \(serverType == .crud ?
        """
              
            new {
                group = "validate-openapi"
                branchRules {
                    includePatterns {
                        "main"
                    }
                }
                machine {
                    baseImage = "docker-upstream.apple.com/dshanley/vacuum:latest"
                }
                build {
                    template = "freestyle:v4:prb"
                    steps {
                        #\"""
                        /usr/local/bin/vacuum lint -dq ./Public/openapi.yaml
                        \"""#
                    }
                }
            }
        }
        """ : "}")

    notify {
      pullRequestComment {
        postOnFailure = false
        postOnSuccess = false
      }
      commitStatus {
        enabled = true
      }
    }
    """
}

func genDockerFile(serverType: ServerType) -> String {
    
    """
    ARG SWIFT_VERSION=6.1
    ARG UBI_VERSION=9

    FROM docker.apple.com/base-images/ubi${UBI_VERSION}/swift${SWIFT_VERSION}-builder AS builder

    WORKDIR /code

    # First just resolve dependencies.
    # This creates a cached layer that can be reused
    # as long as your Package.swift/Package.resolved
    # files do not change.
    COPY ./Package.* ./
    RUN swift package resolve \\
            $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

    # Copy the Sources dir into container
    COPY ./Sources ./Sources
    \(serverType == .crud ? "COPY ./Public ./Public" : "")

    # Build the application, with optimizations
    RUN swift build -c release --product \(serverType == .crud ? "CRUDHTTPServer" : "BareHTTPServer")

    FROM docker.apple.com/base-images/ubi${UBI_VERSION}-minimal/swift${SWIFT_VERSION}-runtime

    USER root
    RUN mkdir -p /app/bin
    COPY --from=builder /code/.build/release/\(serverType == .crud ? "CRUDHTTPServer" : "BareHTTPServer") /app/bin
    \(serverType == .crud ? "COPY --from=builder /code/Public /app/Public" : "")
    RUN mkdir -p /logs \(serverType == .bare ? "&& chown $NON_ROOT_USER_ID /logs" : "")
    \(serverType == .crud ? "# Intentionally run as root, for now." : "USER $NON_ROOT_USER_ID")

    WORKDIR /app
    ENV SWIFT_BACKTRACE=interactive=no,color=no,output-to=/logs,format=json,symbolicate=fast
    CMD /app/bin/\(serverType == .crud ? "CRUDHTTPServer" : "BareHTTPServer") serve
    EXPOSE 8080

    """
}
func genReadMe(serverType: ServerType) -> String {
    """
    # \(serverType.targetName.uppercased())
    
    A simple starter project for a server with the following features:
    
    \(serverType.features)

    ## Configuration/secrets

    ⚠️ This sample project is missing a configuration/secrets reader library for now. 

    We are building one, follow this radar for progress: [rdar://148970365](rdar://148970365) (Swift Configuration: internal preview)

    In the meantime, the recommendation is:
    - for environment variables, use `ProcessInfo.processInfo.environment` directly
    - for JSON/YAML files, use [`JSONDecoder`](https://developer.apple.com/documentation/foundation/jsondecoder)/[`Yams`](https://github.com/jpsim/Yams), respectively, with a [`Decodable`](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types) custom type
    - for Newcastle properties, use the [swift-newcastle-properties](https://github.pie.apple.com/swift-server/swift-newcastle-properties) library directly

    The upcoming Swift Configuration library will offer a unified API to access all of the above, so should be easy to migrate to it once it's ready.

    ## Running locally

    In one Terminal window, start all the services with `docker-compose -f Deploy/Local/docker-compose.yaml up`.

    ## Running published container images (skip the local build)

    Same steps as in "Running locally", just comment out `build:` and uncomment `image:` in the `docker-compose.yaml` file.

    ## Calling locally

    \(serverType.callingLocally)
    ## Enabling Rio

    This sample project comes with a `rio.template.pkl`, where you can just update the docker.apple.com repository you'd like to publish your service to, and rename the file to `rio.pkl` - and be ready to go to onboard to Rio.

    
    \(serverType.deployToKube)
    """
}

func genDockerCompose(server:ServerType) -> String {
    switch server {
    case .bare:
        """
        version: "3.5"
        services:
          bare:
            # Comment out "build:" and uncomment "image:" to pull the existing image from docker.apple.com
            build: ../..
            # image: docker.apple.com/swift-server/starter-projects-bare-http-server:latest
            ports:
              - "8080:8080"

        # yaml-language-server: $schema=https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json
        """
    case .crud:
        """
        version: "3.5"
        services:
          crud:
            # Comment out "build:" and uncomment "image:" to pull the existing image from docker.apple.com
            build: ../..
            # image: docker.apple.com/swift-server/starter-projects-crud-http-server:latest
            ports:
              - "8080:8080"
            environment:
              LOG_FORMAT: keyValue
              LOG_LEVEL: debug
              LOG_FILE: /logs/crud.log
              POSTGRES_URL: postgres://postgres@postgres:5432/postgres?sslmode=disable
              OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
            volumes:
              - ./logs:/logs
            depends_on:
              postgres:
                condition: service_healthy

          postgres:
            image: docker-upstream.apple.com/postgres:latest
            environment:
              POSTGRES_USER: postgres
              POSTGRES_DB: postgres
              POSTGRES_HOST_AUTH_METHOD: trust
            ports:
              - "5432:5432"
            healthcheck:
              test: ["CMD-SHELL", "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"]
              interval: 10s
              timeout: 5s
              retries: 5

          otel-collector:
            image: otel/opentelemetry-collector-contrib:latest
            command: ["--config=/etc/otel-collector-config.yaml"]
            volumes:
              - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
            ports:
              - "4317:4317"  # OTLP gRPC receiver

          prometheus:
            image: prom/prometheus:latest
            entrypoint:
              - "/bin/prometheus"
              - "--log.level=debug"
              - "--config.file=/etc/prometheus/prometheus.yaml"
              - "--storage.tsdb.path=/prometheus"
              - "--web.console.libraries=/usr/share/prometheus/console_libraries"
              - "--web.console.templates=/usr/share/prometheus/consoles"
            volumes:
              - ./prometheus.yaml:/etc/prometheus/prometheus.yaml
            ports:
              - "9090:9090"  # Prometheus web UI

          jaeger:
            image: jaegertracing/all-in-one
            ports:
              - "16686:16686"  # Jaeger Web UI

        # yaml-language-server: $schema=https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json
        """
    }
}

func genOtelCollectorConfig() -> String {
    """
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: "otel-collector:4317"

    exporters:
      debug:  # Data sources: traces, metrics, logs
        verbosity: detailed

      otlp/jaeger:  # Data sources: traces
        endpoint: "jaeger:4317"
        tls:
          insecure: true

    service:
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [otlp/jaeger, debug]

    # yaml-language-server: $schema=https://raw.githubusercontent.com/srikanthccv/otelcol-jsonschema/main/schema.json

    """
}

func genPrometheus() -> String {
    """
    scrape_configs:
      - job_name: "crud"
        scrape_interval: 5s
        metrics_path: "/metrics"
        static_configs:
          - targets: ["crud:8080"]

    # yaml-language-server: $schema=http://json.schemastore.org/prometheus
    """
}

func genOpenAPIFrontend() -> String {
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <link rel="stylesheet" type="text/css" href="//unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <title>Pollercoaster API</title>
    <body>
      <div id="sample" />
      <script src="//unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        window.onload = function() {
          const ui = SwaggerUIBundle({
            url: "openapi.yaml",
            dom_id: "#sample",
            deepLinking: true,
            validatorUrl: "none"
          })
        }
      </script>
    </body>
    </html>
    """
}

func genOpenAPIBackend() -> String {
    """
    openapi: '3.1.0'
    info:
      title: CRUDHTTPServer
      description: Create, read, delete, and list TODOs.
      version: 1.0.0
    servers:
      - url: /api
        description: Invoke methods on this server.
    tags:
      - name: TODOs
    paths:
      /todos:
        get:
          summary: Fetch a list of TODOs.
          operationId: listTODOs
          tags:
            - TODOs
          responses:
            '200':
              description: Returns the list of TODOs.
              content:
                application/json:
                  schema:
                    $ref: '#/components/schemas/PageOfTODOs'
        post:
          summary: Create a new TODO.
          operationId: createTODO
          tags:
            - TODOs
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  $ref: '#/components/schemas/CreateTODORequest'
          responses:
            '201':
              description: The TODO was created successfully.
              content:
                application/json:
                  schema:
                    $ref: '#/components/schemas/TODODetail'
      /todos/{todoId}:
        parameters:
          - $ref: '#/components/parameters/path.todoId'
        get:
          summary: Fetch the details of a single TODO.
          operationId: getTODODetail
          tags:
            - TODOs
          responses:
            '200':
              description: A successful response.
              content:
                application/json:
                  schema:
                    $ref: "#/components/schemas/TODODetail"
            '404':
              description: A TODO with this id was not found.
        delete:
          summary: Delete a TODO.
          operationId: deleteTODO
          tags:
            - TODOs
          responses:
            '204':
              description: Successfully deleted the TODO.
      # Warning: Remove this endpoint in production, or guard it by admin auth.
      # It's here for easy testing of crash log uploading.
      /crash:
        post:
          summary: Trigger a crash for testing crash handling.
          operationId: crash
          tags:
            - Admin
          responses:
            '200':
              description: Won't actually return - the server will crash.
    components:
      parameters:
        path.todoId:
          name: todoId
          in: path
          required: true
          schema:
            type: string
            format: uuid
      schemas:
        PageOfTODOs:
          description: A single page of TODOs.
          properties:
            items:
              type: array
              items:
                $ref: '#/components/schemas/TODODetail'
          required:
            - items
        CreateTODORequest:
          description: The metadata required to create a TODO.
          properties:
            contents:
              description: The contents of the TODO.
              type: string
          required:
            - contents
        TODODetail:
          description: The details of a TODO.
          properties:
            id:
              description: A unique identifier of the TODO.
              type: string
              format: uuid
            contents:
              description: The contents of the TODO.
              type: string
          required:
            - id
            - contents

    """
}

func writeHelloWorld() -> String {
    """
    // The Swift Programming Language
    // https://docs.swift.org/swift-book

    @main
    struct start {
        static func main() {
            print("Hello, world!")
        }
    }

    """
}


enum CrudServerFiles {
    
    static func genTelemetryFile(logLevel: LogLevel, logPath: URL, logFormat: LogFormat, logBufferSize: Int) -> String {
        """
        import ServiceLifecycle
        import Logging
        import Logback
        import Foundation
        import Vapor
        import Metrics
        import Prometheus
        import Tracing
        import OTel
        import OTLPGRPC

        enum LogFormat: String {
            case json = "json"
            case keyValue = "keyValue"
        }

        struct ShutdownService: Service {
            var shutdown: @Sendable () async throws -> Void
            func run() async throws {
                try await gracefulShutdown()
                try await shutdown()
            }
        }

        struct Telemetry {
            var services: [Service]
            var metricsCollector: PrometheusCollectorRegistry
        }

        func configureTelemetryServices() async throws -> Telemetry {

            var services: [Service] = []
            let metricsCollector: PrometheusCollectorRegistry

            let logLevel = Logger.Level.\(logLevel)

            // Logging
            do {
                let logFormat = LogFormat.\(logFormat)
                let logFile = "\(logPath)"
                let logBufferSize: Int = \(logBufferSize)
                print("Logging to file: \\(logFile) at level: \\(logLevel.name) using format: \\(logFormat.rawValue), buffer size: \\(logBufferSize)")

                var logAppenders: [LogAppender] = []
                let logFormatter: LogFormatterProtocol
                switch logFormat {
                case .json:
                    logFormatter = JSONLogFormatter(appName: "CRUDHTTPServer", mode: .full)
                case .keyValue:
                    logFormatter = KeyValueLogFormatter()
                }

                let logDirectory = URL(fileURLWithPath: logFile).deletingLastPathComponent()

                // 1. ensure the folder for the rotating log files exists
                try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

                // 2. create file log appender
                let fileAppender = RollingFileLogAppender(
                    path: logFile,
                    formatter: logFormatter,
                    policy: RollingFileLogAppender.RollingPolicy.size(100_000_000)
                )
                let fileAsyncAppender = AsyncLogAppender(
                    appender: fileAppender,
                    capacity: logBufferSize
                )

                logAppenders.append(fileAsyncAppender)

                // 3. create console log appender
                let consoleAppender = ConsoleLogAppender(formatter: logFormatter)
                let consoleAsyncAppender = AsyncLogAppender(
                    appender: consoleAppender,
                    capacity: logBufferSize
                )
                logAppenders.append(consoleAsyncAppender)

                // 4. start and set the appenders
                logAppenders.forEach { $0.start() }
                let startedLogAppenders = logAppenders

                // 5. create config resolver
                let configResolver = DefaultConfigLogResolver(level: logLevel, appenders: logAppenders)
                Log.addConfigResolver(configResolver)

                // 6. registers `Logback` as the logging backend
                Logback.LogHandler.bootstrap()

                Log.defaultPayload["app_name"] = .string("CRUDHTTPServer")

                services.append(ShutdownService(shutdown: {
                    startedLogAppenders.forEach { $0.stop() }
                }))
            }

            // Metrics
            do {
                let metricsRegistry = PrometheusCollectorRegistry()
                metricsCollector = metricsRegistry
                let metricsFactory = PrometheusMetricsFactory(registry: metricsRegistry)
                MetricsSystem.bootstrap(metricsFactory)
            }

            // Tracing
            do {
                // Generic otel
                let environment = OTelEnvironment.detected()
                let resourceDetection = OTelResourceDetection(detectors: [
                    OTelProcessResourceDetector(),
                    OTelEnvironmentResourceDetector(environment: environment),
                    .manual(OTelResource(attributes: [
                        "service.name": "CRUDHTTPServer",
                    ]))
                ])
                let resource = await resourceDetection.resource(
                    environment: environment, 
                    logLevel: logLevel
                )

                let tracer = OTelTracer(
                    idGenerator: OTelRandomIDGenerator(),
                    sampler: OTelConstantSampler(isOn: true),
                    propagator: OTelW3CPropagator(),
                    processor: OTelBatchSpanProcessor(
                        exporter: try OTLPGRPCSpanExporter(
                            configuration: .init(environment: environment)
                        ),
                        configuration: .init(environment: environment)
                    ),
                    environment: environment,
                    resource: resource
                )
                services.append(tracer)
                InstrumentationSystem.bootstrap(tracer)
            }

            return .init(services: services, metricsCollector: metricsCollector)
        }

        extension Logger {
            @TaskLocal
            static var _current: Logger?
            
            static var current: Logger {
                get throws {
                    guard let _current else {
                        struct NoCurrentLoggerError: Error {}
                        throw NoCurrentLoggerError()
                    }
                    return _current
                }
            }
        }

        struct RequestLoggerInjectionMiddleware: Vapor.AsyncMiddleware {
            func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
                return try await Logger.$_current.withValue(request.logger) {
                    return try await next.respond(to: request)
                }
            }
        }

        """
    }
    static func getServerService() -> String {
        """
        import Vapor
        import ServiceLifecycle
        import OpenAPIVapor
        import AsyncHTTPClient

        func configureServer(_ app: Application) async throws -> ServerService {
            app.middleware.use(RequestLoggerInjectionMiddleware())
            app.middleware.use(TracingMiddleware())
            app.traceAutoPropagation = true

            // A health endpoint.
            app.get("health") { _ in
                "ok\\n"
            }

            // Add Vapor middleware to serve the contents of the Public/ directory.
            app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

            // Redirect "/" and "/openapi"  to openapi.html, which serves the Swagger UI.
            app.get("openapi") { $0.redirect(to: "/openapi.html", redirectType: .normal) }
            app.get { $0.redirect(to: "/openapi.html", redirectType: .normal) }

            // Create app state.
            let handler = APIHandler(db: app.db)

            // Register the generated handlers.
            let transport = VaporTransport(routesBuilder: app)
            try handler.registerHandlers(
                on: transport,
                serverURL: Servers.Server1.url(),
                configuration: .init(),
                middlewares: []
            )

            // Uncomment the code below if you'd like to make upstream HTTP calls.
            // let httpClient = HTTPClient()
            // let responseStatus = try await httpClient
            //     .execute(.init(url: "https://apple.com/"), deadline: .distantFuture)
            //     .status

            return ServerService(app: app)
        }

        struct ServerService: Service {
            var app: Application
            func run() async throws {
                try await app.execute()
            }
        }
        """
    }
    
    static func getOpenAPIConfig() -> String {
        """
        generate:
          - types
          - server
        namingStrategy: idiomatic

        """
    }
    
    static func genAPIHandler() -> String {
        """
        import OpenAPIRuntime
        import HTTPTypes
        import Fluent
        import Foundation
    
        /// The implementation of the API described by the OpenAPI document.
        ///
        /// To make changes, add a new operation in the openapi.yaml file, then rebuild
        /// and add the suggested corresponding method in this type.
        struct APIHandler: APIProtocol {
    
            var db: Database
            
            func listTODOs(
                _ input: Operations.ListTODOs.Input
            ) async throws -> Operations.ListTODOs.Output {
                let dbTodos = try await db.query(DB.TODO.self).all()
                let apiTodos = try dbTodos.map { todo in
                    Components.Schemas.TODODetail(
                        id: try todo.requireID(),
                        contents: todo.contents
                    )
                }
                return .ok(.init(body: .json(.init(items: apiTodos))))
            }
    
            func createTODO(
                _ input: Operations.CreateTODO.Input
            ) async throws -> Operations.CreateTODO.Output {
                switch input.body {
                case .json(let todo):
                    let newId = UUID().uuidString
                    let contents = todo.contents
                    let dbTodo = DB.TODO()
                    dbTodo.id = newId
                    dbTodo.contents = contents
                    try await dbTodo.save(on: db)
                    return .created(.init(body: .json(.init(
                        id: newId,
                        contents: contents
                    ))))
                }
            }
    
            func getTODODetail(
                _ input: Operations.GetTODODetail.Input
            ) async throws -> Operations.GetTODODetail.Output {
                let id = input.path.todoId
                guard let foundTodo = try await DB.TODO.find(id, on: db) else {
                    return .notFound
                }
                return .ok(.init(body: .json(.init(
                    id: id,
                    contents: foundTodo.contents
                ))))
            }
    
            func deleteTODO(
                _ input: Operations.DeleteTODO.Input
            ) async throws -> Operations.DeleteTODO.Output {
                try await db.query(DB.TODO.self).filter(\\.$id == input.path.todoId).delete()
                return .noContent(.init())
            }
    
            // Warning: Remove this endpoint in production, or guard it by admin auth.
            // It's here for easy testing of crash log uploading.
            func crash(_ input: Operations.Crash.Input) async throws -> Operations.Crash.Output {
                // Trigger a fatal error for crash testing
                fatalError("Crash endpoint triggered for testing purposes - this is intentional crash handling behavior")
            }
        }
    """
        
    }
    
    static func genEntryPointFile(
    serverAddress: String,
    serverPort: Int
    ) -> String {
        """
        import Vapor
        import ServiceLifecycle
        import OpenAPIVapor
        import Foundation

        @main
        struct Entrypoint {
            static func main() async throws {

                // Configure telemetry
                let telemetry = try await configureTelemetryServices()

                // Create the server
                let app = try await Vapor.Application.make()
                do {
                    app.http.server.configuration.address = .hostname(
                        "\(serverAddress)",
                        port: \(serverPort)
                    )

                    // Configure the metrics endpoint
                    app.get("metrics") { _ in
                        var buffer: [UInt8] = []
                        buffer.reserveCapacity(1024)
                        telemetry.metricsCollector.emit(into: &buffer)
                        return String(decoding: buffer, as: UTF8.self)
                    }

                    // Configure the database
                    try await configureDatabase(app: app)

                    // Configure the server
                    let serverService = try await configureServer(app)

                    // Start the service group, which spins up all the service above
                    let services: [Service] = telemetry.services + [serverService]
                    let serviceGroup = ServiceGroup(
                        services: services,
                        gracefulShutdownSignals: [.sigint],
                        cancellationSignals: [.sigterm],
                        logger: app.logger
                    )
                    try await serviceGroup.run()
                } catch {
                    try await app.asyncShutdown()
                    app.logger.error("Top level error", metadata: ["error": "\\(error)"])
                    try FileHandle.standardError.write(contentsOf: Data("Final error: \\(error)\\n".utf8))
                    exit(1)
                }
            }
        }

        """
    }
    
}

enum DatabaseFile {
    
    static func genDatabaseFileWithMTLS(
        mtlsPath: URL,
        mtlsKeyPath: URL,
        mtlsAdditionalTrustRoots: [URL],
        postgresURL: URL
    ) -> String {

        func escape(_ string: String) -> String {
            return string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        
        let postgresURLString = escape(postgresURL.absoluteString)
        let certPathString = escape(mtlsPath.path)
        let keyPathString = escape(mtlsKeyPath.path)
        let trustRootsStrings = mtlsAdditionalTrustRoots
            .map { "\"\(escape($0.path))\"" }
            .joined(separator: ", ")
        
        return """
        import FluentPostgresDriver
        import PostgresKit
        import Fluent
        import Vapor
        import Foundation
        
        func configureDatabase(app: Application) async throws {
            let postgresURL = URL(string:"\(postgresURLString)")!
            var postgresConfiguration = try SQLPostgresConfiguration(url: postgresURL)
            app.logger.info("Loading MTLS certificates for PostgreSQL")
            let certPath = "\(certPathString)"
            let keyPath = "\(keyPathString)"
            let additionalTrustRoots: [String] = [\(trustRootsStrings)]
            var tls: TLSConfiguration = .makeClientConfiguration()

            enum PostgresMtlsError: Error, CustomStringConvertible {
                case certChain(String, Error)
                case privateKey(String, Error)
                case additionalTrustRoots(String, Error)
                case nioSSLContextCreation(Error)

                var description: String {
                    switch self {
                    case .certChain(let string, let error):
                        return "Cert chain failed: \\(string): \\(error)"
                    case .privateKey(let string, let error):
                        return "Private key failed: \\(string): \\(error)"
                    case .additionalTrustRoots(let string, let error):
                        return "Additional trust roots failed: \\(string): \\(error)"
                    case .nioSSLContextCreation(let error):
                        return "NIOSSLContext creation failed: \\(error)"
                    }
                }
            }

            do {
                tls.certificateChain = try NIOSSLCertificate.fromPEMFile(certPath).map { .certificate($0) }
            } catch {
                throw PostgresMtlsError.certChain(certPath, error)
            }
            do {
                tls.privateKey = try .privateKey(.init(file: keyPath, format: .pem))
            } catch {
                throw PostgresMtlsError.privateKey(keyPath, error)
            }
            do {
                tls.additionalTrustRoots = try additionalTrustRoots.map {
                    try .certificates(NIOSSLCertificate.fromPEMFile($0))
                }
            } catch {
                throw PostgresMtlsError.additionalTrustRoots(additionalTrustRoots.joined(separator: ","), error)
            }
            do {
                postgresConfiguration.coreConfiguration.tls = .require(try NIOSSLContext(configuration: tls))
            } catch {
                throw PostgresMtlsError.nioSSLContextCreation(error)
            }
            app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)
            app.migrations.add([
                Migrations.CreateTODOs(),
            ])
            do {
                try await app.autoMigrate()
            } catch {
                app.logger.error("Database setup error", metadata: ["error": .string(String(reflecting: error))])
                throw error
            }
        }

        enum DB {
            final class TODO: Model, @unchecked Sendable {
                static let schema = "todos"

                @ID(custom: "id", generatedBy: .user)
                var id: String?

                @Field(key: "contents")
                var contents: String
            }
        }

        enum Migrations {
            struct CreateTODOs: AsyncMigration {
                func prepare(on database: Database) async throws {
                    try await database.schema(DB.TODO.schema)
                        .field("id", .string, .identifier(auto: false))
                        .field("contents", .string, .required)
                        .create()
                }

                func revert(on database: Database) async throws {
                    try await database
                        .schema(DB.TODO.schema)
                        .delete()
                }
            }
        }
        """
    }

    
    static func genDatabaseFileWithoutMTLS(postgresURL: URL) -> String {
        
        func escape(_ string: String) -> String {
            return string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        
        let postgresURLString = escape(postgresURL.absoluteString)

        return """
        import FluentPostgresDriver
        import PostgresKit
        import Fluent
        import Vapor
        import Foundation
        
        func configureDatabase(app: Application) async throws {
            let postgresURL = "\(postgresURLString)"
            var postgresConfiguration = try SQLPostgresConfiguration(url: postgresURL)
            app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)
            app.migrations.add([
                Migrations.CreateTODOs(),
            ])
            do {
                try await app.autoMigrate()
            } catch {
                app.logger.error("Database setup error", metadata: ["error": .string(String(reflecting: error))])
                throw error
            }
        }
        
        enum DB {
            final class TODO: Model, @unchecked Sendable {
                static let schema = "todos"
        
                @ID(custom: "id", generatedBy: .user)
                var id: String?
        
                @Field(key: "contents")
                var contents: String
            }
        }
        
        enum Migrations {
            struct CreateTODOs: AsyncMigration {
                func prepare(on database: Database) async throws {
                    try await database.schema(DB.TODO.schema)
                        .field("id", .string, .identifier(auto: false))
                        .field("contents", .string, .required)
                        .create()
                }
        
                func revert(on database: Database) async throws {
                    try await database
                        .schema(DB.TODO.schema)
                        .delete()
                }
            }
        }
        """
    }

}

enum BareServerFiles {
    static func genEntryPointFile(
    serverAddress: String,
    serverPort: Int
    ) -> String {
        """
        import Vapor

        @main
        struct Entrypoint {
            static func main() async throws {

                // Create the server
                let app = try await Vapor.Application.make()
                app.http.server.configuration.address = .hostname(
                    "\(serverAddress)",
                    port: \(serverPort)
                )
                try await configureServer(app)
                try await app.execute()
            }
        }

        """
    }
    
    static func genServerFile() -> String {
        """
        import Vapor

        func configureServer(_ app: Application) async throws {

            // A health endpoint.
            app.get("health") { _ in
                "ok\\n"
            }
        }
        """
    }
}



@main
struct ServerGenerator: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "server-generator",
        abstract: "This template gets you started with starting to experiment with servers in swift.",
        subcommands: [
            CRUD.self,
            Bare.self
        ],
    )

    @OptionGroup(visibility: .hidden)
    var packageOptions: PkgDir

    mutating func run() throws {
        guard let pkgDir = self.packageOptions.pkgDir else {
            throw ValidationError("No --pkg-dir was provided.")
        }
        let packageDir = FilePath(pkgDir)
        // Remove the main.swift left over from the base executable template, if it exists
        try? fs.shared.rm(atPath: packageDir / "Sources")
    }
}

// MARK: - CRUD Command
public struct CRUD: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "crud",
        abstract: "Generate CRUD server",
        subcommands: [MTLS.self, NoMTLS.self]
    )

    @ParentCommand var serverGenerator: ServerGenerator

    @Option(help: "Set the logging level.")
    var logLevel: LogLevel = .debug

    @Option(help: "Set the logging format.")
    var logFormat: LogFormat = .json

    
    @Option(help: "Set the logging file path.")
    var logPath: String = "/tmp/crud_server.log"

    @Option(help: "Set logging buffer size (in bytes).")
    var logBufferSize: Int = 1024

    @OptionGroup
    var serverOptions: SharedOptionsServers
    
    
    public init() {}
    mutating public func run() throws {
        
        try serverGenerator.run()

        guard let pkgDir = self.serverGenerator.packageOptions.pkgDir else {
            throw ValidationError("No --pkg-dir was provided.")
        }

        let packageDir = FilePath(pkgDir)

        
        guard let url = URL(string: logPath) else {
            throw ValidationError("Invalid log path: \(logPath)")
        }

        let logURLPath = CLIURL(url)

        // Start from scratch with the Package.swift
        try? fs.shared.rm(atPath: packageDir / "Package.swift")

        // Create base package
        try packageSwift(serverType: .crud).write(toFile: packageDir / "Package.swift")

        if serverOptions.readMe.readMe {
            try genReadMe(serverType: .crud).write(toFile: packageDir / "README.md")
        }
        try genRioTemplatePkl(serverType: .crud).write(toFile: packageDir / "rio.template.pkl")
        try genDockerFile(serverType: .crud).write(toFile: packageDir / "Dockerfile.txt")

        //Create files for local folder
        
        try genDockerCompose(server: .crud).write(toFile: packageDir / "Deploy/Local/docker-compose.yaml")
        try genOtelCollectorConfig().write(toFile: packageDir / "Deploy/Local/otel-collector-config.yaml")
        try genPrometheus().write(toFile: packageDir / "Deploy/Local/prometheus.yaml")
        
        //Create files for public folder
        try genOpenAPIBackend().write(toFile: packageDir / "Public/openapi.yaml")
        try genOpenAPIFrontend().write(toFile: packageDir / "Public/openapi.html")
        
        //Create source files
        try CrudServerFiles.genAPIHandler().write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/APIHandler.swift")
        try CrudServerFiles.getOpenAPIConfig().write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/openapi-generator-config.yaml")
        try CrudServerFiles.getServerService().write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/ServerService.swift")
        try CrudServerFiles.genEntryPointFile(serverAddress: self.serverOptions.host, serverPort: self.serverOptions.port).write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/EntryPoint.swift")
        try CrudServerFiles.genTelemetryFile(logLevel: self.logLevel, logPath: logURLPath.url, logFormat: self.logFormat, logBufferSize: self.logBufferSize).write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/Telemetry.swift")

        let targetPath = packageDir / "Public/openapi.yaml"
        let linkPath = packageDir / "Sources/\(ServerType.crud.targetName)/openapi.yaml"

        // Compute the relative path from linkPath's parent to targetPath
        let relativeTarget = targetPath.relative(to: linkPath.removingLastComponent())

        try fs.shared.csl(atPath: linkPath, pointTo: relativeTarget)
    }
}

// MARK: - MTLS Subcommand
struct MTLS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mtls",
        abstract: "Set up mutual TLS"
    )

    @ParentCommand var crud: CRUD

    @Option(help: "Path to MTLS certificate.")
    var mtlsPath: CLIURL

    @Option(help: "Path to MTLS private key.")
    var mtlsKeyPath: CLIURL

    @Option(help: "Paths to additional trust root certificates (PEM format).")
    var mtlsAdditionalTrustRoots: [CLIURL] = []

    @Option(help: "PostgreSQL database connection URL.")
    var postgresURL: String = "postgres://postgres@localhost:5432/postgres?sslmode=disable"

    mutating func run() throws {
        
        try crud.run()
        guard let pkgDir = self.crud.serverGenerator.packageOptions.pkgDir else {
            throw ValidationError("No --pkg-dir was provided.")
        }
        
        guard let url = URL(string: postgresURL) else {
            throw ValidationError("Invalid URL: \(postgresURL)")
        }

        let postgresURLComponents = CLIURL(url)


        let packageDir = FilePath(pkgDir)
        
        let urls = self.mtlsAdditionalTrustRoots.map { $0.url }

        try DatabaseFile.genDatabaseFileWithMTLS(mtlsPath: self.mtlsPath.url, mtlsKeyPath: self.mtlsKeyPath.url, mtlsAdditionalTrustRoots: urls, postgresURL: postgresURLComponents.url).write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/Database.swift")
    }
}

struct NoMTLS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "no-mtls",
        abstract: "Do not set up mutual TLS"
    )

    @ParentCommand var crud: CRUD

    @Option(help: "PostgreSQL database connection URL.")
    var postgresURL: String = "postgres://postgres@localhost:5432/postgres?sslmode=disable"

    mutating func run() throws {
    
        
        try crud.run()

        guard let pkgDir = self.crud.serverGenerator.packageOptions.pkgDir else {
            throw ValidationError("No --pkg-dir was provided.")
        }

        guard let url = URL(string: postgresURL) else {
            throw ValidationError("Invalid URL: \(postgresURL)")
        }

        let postgresURLComponents = CLIURL(url)

        
        let packageDir = FilePath(pkgDir)
        
        try DatabaseFile.genDatabaseFileWithoutMTLS(postgresURL: postgresURLComponents.url).write(toFile: packageDir / "Sources/\(ServerType.crud.targetName)/Database.swift")
    }
}


// MARK: - Bare Command
struct Bare: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bare",
        abstract: "Generate a bare server"
    )

    @ParentCommand var serverGenerator: ServerGenerator

    @OptionGroup
    var serverOptions: SharedOptionsServers

    mutating func run() throws {
        
        try self.serverGenerator.run()
        
        guard let pkgDir = self.serverGenerator.packageOptions.pkgDir else {
            throw ValidationError("No --pkg-dir was provided.")
        }
        
        let packageDir = FilePath(pkgDir)

        // Start from scratch with the Package.swift
        try? fs.shared.rm(atPath: packageDir / "Package.swift")

        //Generate base package
        try packageSwift(serverType: .bare).write(toFile: packageDir / "Package.swift")
        if serverOptions.readMe.readMe {
            try genReadMe(serverType: .bare).write(toFile: packageDir / "README.md")
        }
        try genRioTemplatePkl(serverType: .bare).write(toFile: packageDir / "rio.template.pkl")
        try genDockerFile(serverType: .bare).write(toFile: packageDir / "Dockerfile.txt")

        
        //Generate files for Deployment
        try genDockerCompose(server: .bare).write(toFile: packageDir / "Deploy/Local/docker-compose.yaml")

        
        // Generate sources files for bare http server
        try BareServerFiles.genEntryPointFile(serverAddress: self.serverOptions.host, serverPort: self.serverOptions.port).write(toFile: packageDir / "Sources/\(ServerType.bare.targetName)/Entrypoint.swift")
        try BareServerFiles.genServerFile().write(toFile: packageDir / "Sources/\(ServerType.bare.targetName)/Server.swift")

    }
}

struct CLIURL: ExpressibleByArgument, Decodable {
    let url: URL

    // Failable init for CLI arguments (strings)
    init?(argument: String) {
        guard let url = URL(string: argument) else { return nil }
        self.url = url
    }

    // Non-failable init for defaults from URL type
    init(_ url: URL) {
        self.url = url
    }

    // Conform to Decodable by decoding a string and parsing URL
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let urlString = try container.decode(String.self)
        guard let url = URL(string: urlString) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid URL string.")
        }
        self.url = url
    }
}


// MARK: - Shared option commands that are used to show inheritances of arguments and flags
struct PkgDir: ParsableArguments {
    @Option(help: .hidden)
    var pkgDir: String?
}

struct readMe: ParsableArguments {
    @Flag(help: "Add a README.md file with an introduction to the server + configuration?")
    var readMe: Bool = false
}

struct SharedOptionsServers: ParsableArguments {
    @OptionGroup
    var readMe: readMe
    
    @Option(help: "Server Port")
    var port: Int = 8080
    
    @Option(help: "Server Host")
    var host: String = "0.0.0.0"
}

public enum LogLevel: String, ExpressibleByArgument, CaseIterable, CustomStringConvertible {
    case trace, debug, info, notice, warning, error, critical
    public var description: String { rawValue }
}

public enum LogFormat: String, ExpressibleByArgument, CaseIterable, CustomStringConvertible {
    case json, keyValue
    public var description: String { rawValue }
}
