# Swift package templating example

---

This project provides a simple example to show how to author a template to generate Swift projects, utilizing the template feature included within the `swift package init` command of the Swift Package Manager.

## Available templates:

### HelloTemplate

The HelloTemplate template generates a simple package with a manifest and a sources directory. The template requires users to specify the name of their package, alongside the inclusion of a `README.md`.

### TemplatingEngineTemplate

The TemplatingEngineTemplate generates a basic package structure and produces a `User.swift` file using the Stencil templating engine. It serves as an example of how a template can integrate an external templating engine into its generation workflow.

### PartsService

The parts service template generates a REST service using Hummingbird (app server), and Fluent (ORM) with a configurable database management system (SQLite3, and PostgreSQL). The template includes various switches to customize your project.

Invoke the parts service generator like this:

```
swift run parts-service --pkg-dir <new_package_dir>
```

Find the additional information and parameters by invoking `--help` on the `parts-service`:

```
swift run parts-service --help
```

### ServerTemplate

The ServerTemplate is a felxible template designed to scaffold a server based on the user-defined configuration options. It demonstrates hw branching logic can be applied within templates, allowing users to tailor the generated output to their specific needs. With ServerTemplate, users can choose between a bare server or a CRUD-enabled server. 
Users are encouraged, when prompted, to include a `README.md` that is tailored to the chosen configuration, providing helpful context and usage guidance for the newly created server package.
