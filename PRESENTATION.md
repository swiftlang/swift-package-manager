{.presentation theme=system}
# SwiftPM Workspaces

**SE-NNNN · A user's tour**

{.slide}
## Agenda

- The problem today
- The `Workspace.swift` manifest
- Member dependencies: `.workspaceMember` and `.workspaceInherited`
- The `swift workspace` command surface
- **Live demo:** scaffold → build → test → override
- State files, mirrors, and migration
- What's next

~~~{.present}
duration: 60
~~~

{.notes}
Goal: by the end of this talk the audience knows exactly what Workspace.swift looks like, what `swift workspace` can do, and when to reach for it. Keep this ~90s.

{.slide}
## The problem today

Modern Swift apps are made of **many packages** — `app`, `logging`, `networking`, `storage`. Three bad options exist today:

- **Publish internal libs to a registry** — unnecessary friction for internal-only code {.build}
- **Chain `.package(path: "../lib-a")`** — each package resolves independently, so `swift-nio` drifts to different versions across siblings {.build}
- **`--multiroot-data-file` with an `.xcworkspace`** — Xcode-specific, hidden flag, unclear semantics for non-Xcode users {.build}

~~~{.present}
duration: 90
enter: slide-up
~~~

{.notes}
Call out the drift problem explicitly — it's the one that bites teams in production. Two members both depend on swift-nio "from 2.0", they resolve independently, and now you've got 2.65.0 in one and 2.68.0 in another. Fun bugs.

{.slide}
## Prior art

> Cargo, Yarn, and Pants all have workspaces as first-class citizens. Swift didn't.

{.build}
SwiftPM already had the plumbing — `PackageGraphRootInput.packages` is a `[AbsolutePath]`, PubGrub handles N unversioned roots via `<synthesized-root>`. What was missing: a **SwiftPM-native user surface** for declaring one.

~~~{.present}
duration: 60
~~~

{.slide}
## The solution — `Workspace.swift`

A new manifest at your repo root. Lists members. Optionally declares workspace-wide dependencies.

~~~swift
// swift-tools-version: 999.0
import PackageDescription

let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
        "packages/lib-b",
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    ],
)
~~~

{.notes}
One Package.resolved. One .build/. One source of truth for every external dep. Members still have their own Package.swift — this doesn't replace them, it coordinates them.

~~~{.present}
duration: 120
~~~

{.slide}
## Member → member references

Inside a member's `Package.swift`, reach siblings by **identity**, not path:

~~~swift
// packages/app/Package.swift
let package = Package(
    name: "app",
    dependencies: [
        .package(workspaceMember: "lib-a"),
        .package(workspaceMember: "lib-b"),
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [
                .product(name: "LibA", package: "lib-a"),
            ],
        ),
    ],
)
~~~

{.notes}
No ../relative/path/juggling. Rename a sibling's directory, the identity stays the same.

~~~{.present}
duration: 90
~~~

{.slide}
## Inherited external dependencies

Reach workspace-level deps by identity. Traits are per-member:

~~~swift
// packages/app/Package.swift
dependencies: [
    .package(workspaceInherited: "swift-nio"),
    .package(workspaceInherited: "swift-log", traits: ["structured"]),
]
~~~

- Version is **workspace-authoritative** — members cannot override {.build}
- Traits are **unioned** across workspace + member {.build}
- Unknown identity → hard error at resolve, listing what *is* declared {.build}

~~~{.present}
duration: 120
~~~

{.slide}
## The CLI — `swift workspace`

A new top-level command tree, mirroring `swift package-registry` and `swift sdk`:

~~~sh
swift workspace init --members packages/app:executable packages/lib-a
swift workspace add-member packages/lib-b --scaffold --type library
swift workspace list-members
swift workspace remove-member packages/lib-b

swift workspace add-dependency url https://github.com/apple/swift-nio --from 2.0.0
swift workspace add-dependency registry apple.swift-log --from 1.0.0

swift workspace override add path lib-a ../local-checkout-of-lib-a
swift workspace override list --format json

swift workspace dump-workspace
swift workspace resolve      # same impl as `swift package resolve`
~~~

{.notes}
Why a top-level `swift workspace`? Same precedent as `swift package-registry`, `swift package-collection`, `swift sdk`. Every workspace-scope op discoverable under one prefix. `swift package init` is untouched.

~~~{.present}
duration: 120
~~~

{.slide}
## Everyday commands just work

~~~sh
cd workspace-root
swift build                    # builds every member
swift test                     # runs every member's tests, one xUnit report
swift run app                  # ambiguous names list candidates + members
~~~

~~~sh
cd packages/app
swift build                    # just this member, workspace-shared graph
swift build --package lib-a    # pick any member from anywhere
~~~

- Single `Package.resolved` at workspace root
- Single `.build/` at workspace root
- `swift package update --package app` restricts fresh pins to `app`'s subtree

~~~{.present}
duration: 120
~~~

{.slide}
## Local overrides — redirect without editing

~~~sh
swift workspace override add path some-lib ../local-some-lib
swift workspace override add url foo https://github.com/me/foo-fork --branch main
swift workspace override remove some-lib
~~~

- Writes to `.swiftpm/configuration/workspace-overrides.json` — developer-local, don't commit
- Folds into the workspace `originHash` → next command re-resolves
- Supersedes `swift package edit` under a workspace (which hard-errors with an actionable pointer here)

~~~{.present}
duration: 90
~~~

{.slide}
## Demo — what we'll do

Three acts, ~5 minutes:

- **Scaffold** a workspace with two members using `swift workspace init`
- **Build and test** across members with a shared external dep
- **Override** that dep to a local checkout, re-resolve, prove it stuck

{.notes}
Switch out of present mode here (Escape), run the demo in a real terminal, come back.

~~~{.present}
duration: 30
~~~

{.slide}
## Demo · Act 1 — scaffold

~~~sh
mkdir ~/demo-workspace && cd ~/demo-workspace

swift workspace init \
    --members packages/app:executable packages/lib-a

swift workspace list-members
# packages/app      (app)
# packages/lib-a    (lib-a)

swift workspace add-dependency url \
    https://github.com/apple/swift-log --from 1.5.0

cat Workspace.swift
~~~

{.notes}
Point out: Workspace.swift exists, two Package.swift files were scaffolded, swift-log appears in dependencies: block. No .build/ yet.

~~~{.present}
duration: 90
~~~

{.slide}
## Demo · Act 2 — wire it up and build

~~~swift
// packages/app/Package.swift — hand-edit after scaffold
dependencies: [
    .package(workspaceMember: "lib-a"),
    .package(workspaceInherited: "swift-log"),
],
~~~

~~~sh
swift build                    # resolves swift-log once, builds both members
swift test                     # one xUnit report at workspace root
cat Package.resolved           # single file at workspace root
ls .build                      # single build dir at workspace root
~~~

{.notes}
If asked: yes, swift-log is only fetched once even though both members could consume it. That's the whole point.

~~~{.present}
duration: 120
~~~

{.slide}
## Demo · Act 3 — override to a local checkout

~~~sh
git -C ~ clone https://github.com/apple/swift-log swift-log-local
swift workspace override add path swift-log ~/swift-log-local
swift workspace override list

swift build                    # re-resolves, picks up local checkout
swift workspace override remove swift-log  # cleanup
~~~

- Overrides fold into `originHash` — no manual `resolve` needed
- Removing the last override deletes the file entirely

~~~{.present}
duration: 90
~~~

{.slide}
## State, mirrors, migration

- **State anchors at workspace root** — `.build/`, `Package.resolved`, `.swiftpm/configuration/`
- Pre-existing per-member state → **trailing warning** listing what was ignored
- Opt out per-kind: `.member(path:, ignoredStateDirectories: [.packageResolved])`
- **Mirrors are workspace-wide** — one `mirrors.json` at the workspace root
- `--multiroot-data-file` + `Workspace.swift` → **hard error** at CLI init

~~~{.present}
duration: 90
~~~

{.slide}
## What's next

- **Workspace-of-workspaces** — compose team workspaces into a build-of-builds
- **Workspace-level build settings** — shared Swift/C/linker flags, strict-concurrency floors
- **Named build & test combinations** — `swift workspace test --combination pr-fast`
- **Publishing a member standalone** — materialize `.workspaceInherited` / `.workspaceMember` on publish
- **Turn on the `--package-path` deprecation warning** — scaffolded, waiting for ecosystem to migrate

~~~{.present}
duration: 60
~~~

{.slide}
## Thanks

Questions?

> SE proposal: `swift-evolution/proposals/NNNN-swiftpm-workspaces.md`
> Implementation: Phases 0–17 on `bkhouri/t/main/poc_workspaces_phase*` branches

{.notes}
Timing budget: ~17 minutes if every slide hits its duration. Padding room on the demo acts.

---

The deck runs ~17 minutes if every slide hits its budget (totals sum to ~1,110s = 18.5 min including transitions). Press `p` or click the icon beside the title to enter Present mode — the sh21 pane shows live elapsed-time + per-slide budget tracking, and the fullscreen window goes to your second display if you have one.

If you'd like me to also save it to disk so you can version it alongside the proposal:

~~~ sh {.next}
mkdir -p /Users/bkhouri/Documents/git/public/swiftlang/swift-package-manager-3/plans/presentations
cat > /Users/bkhouri/Documents/git/public/swiftlang/swift-package-manager-3/plans/presentations/swiftpm-workspaces-user-tour.md <<'EOF'
<paste-the-deck-above>
EOF
ls -la /Users/bkhouri/Documents/git/public/swiftlang/swift-package-manager-3/plans/presentations/
~~~

Or if you'd like me to adjust the balance — more demo time, drop a slide, add a slide on `swift workspace config` mirrors, or shift to light theme — tell me which:

~~~ sh {.option}
echo "Tweak the deck: <e.g. 'add a slide on mirrors', 'swap to theme=light', 'extend demo to 8 min', 'drop the prior-art slide'>"
history | claude21
~~~
```
