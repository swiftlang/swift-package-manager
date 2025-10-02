# Swift package templating example

---

This template project is a simple example of how a template author can create a template and generate a swift projects, utilizing the `swift package init` capability in swift package manager (to come).

## Parts Service

The parts service template can generate a REST service using Hummingbird (app server), and Fluent (ORM) with configurable database management system (SQLite3, and PostgreSQL). There are various switches to customize your project.

Invoke the parts service generator like this:

```
swift run parts-service --pkg-dir <new_package_dir>
```

You can find the additional information and parameters by invoking the help:

```
swift run parts-service --help
```
