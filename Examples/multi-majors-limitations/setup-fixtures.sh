#!/bin/bash
# Creates the local git repositories the limitation examples depend on, so nothing needs the network.
#
#   /tmp/multi-major-fixtures/Shared   tags 1.0.0 2.0.0 3.0.0   (two Swift modules: Shared -> SharedSupport)
#   /tmp/multi-major-fixtures/SharedC  tags 1.0.0 2.0.0         (Swift module wrapping a C target)
#
# The Package.swift files in this directory reference these as file:///tmp/multi-major-fixtures/<name>.
# Re-running the script wipes and recreates the repos (and the tags), which is handy after editing a template.
set -euo pipefail

ROOT=/tmp/multi-major-fixtures
rm -rf "$ROOT"
mkdir -p "$ROOT"

commit_and_tag() {
  local dir=$1 tag=$2
  git -C "$dir" add -A
  git -C "$dir" -c user.name=fixture -c user.email=fixture@example.com commit -q -m "release $tag"
  git -C "$dir" tag "$tag"
}

# --- Shared ------------------------------------------------------------------------------------
# Every major has the same shape (so the same module names collide) but differs in API and in a
# piece of process-global state, which lets the examples observe which major a caller really got.
make_shared() {
  local major=$1
  local dir=$ROOT/Shared
  [ -d "$dir/.git" ] || git -C "$ROOT" init -q Shared
  find "$dir" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
  mkdir -p "$dir/Sources/Shared" "$dir/Sources/SharedSupport"

  cat > "$dir/Package.swift" <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shared",
    products: [
        .library(name: "Shared", targets: ["Shared"]),
    ],
    targets: [
        .target(name: "SharedSupport"),
        .target(name: "Shared", dependencies: ["SharedSupport"]),
    ]
)
EOF

  cat > "$dir/Sources/SharedSupport/Support.swift" <<EOF
public enum SharedSupport {
    public static let major = $major
    /// Process-global state. If two majors really are separate modules, each gets its own copy.
    public static var log: [String] = []
}
EOF

  cat > "$dir/Sources/Shared/Shared.swift" <<EOF
import SharedSupport

public struct Token: CustomStringConvertible {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { "Token(v$major):\(value)" }
}

public enum SharedInfo {
    public static let major = SharedSupport.major
    public static func register(_ name: String) { SharedSupport.log.append("v$major:\(name)") }
    public static var registry: [String] { SharedSupport.log }
    /// Module-qualified name of Token, e.g. "Shared_v2.Token" once aliasing has been applied.
    public static var tokenTypeName: String { String(reflecting: Token.self) }
}
EOF

  # API that only exists in some majors.
  if [ "$major" = 1 ]; then
    cat >> "$dir/Sources/Shared/Shared.swift" <<EOF

extension SharedInfo {
    /// Removed in 2.0.0.
    public static func legacyOnly() -> String { "legacyOnly (v1)" }
}
EOF
  else
    cat >> "$dir/Sources/Shared/Shared.swift" <<EOF

extension SharedInfo {
    /// Added in 2.0.0.
    public static func modernOnly() -> String { "modernOnly (v$major)" }
}
EOF
  fi

  commit_and_tag "$dir" "$major.0.0"
}

for major in 1 2 3; do make_shared "$major"; done

# --- SharedC -----------------------------------------------------------------------------------
# Both majors define the same C symbols. Module aliasing only renames Swift modules, so linking
# both majors into one binary should hit a duplicate-symbol error.
make_shared_c() {
  local major=$1
  local dir=$ROOT/SharedC
  [ -d "$dir/.git" ] || git -C "$ROOT" init -q SharedC
  find "$dir" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
  mkdir -p "$dir/Sources/SharedC" "$dir/Sources/CSharedC/include"

  cat > "$dir/Package.swift" <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedC",
    products: [
        .library(name: "SharedC", targets: ["SharedC"]),
    ],
    targets: [
        .target(name: "CSharedC"),
        .target(name: "SharedC", dependencies: ["CSharedC"]),
    ]
)
EOF

  cat > "$dir/Sources/CSharedC/include/CSharedC.h" <<EOF
#ifndef CSHAREDC_H
#define CSHAREDC_H
int shared_c_version(void);
#endif
EOF

  cat > "$dir/Sources/CSharedC/CSharedC.c" <<EOF
#include "CSharedC.h"
int shared_c_version(void) { return $major; }
EOF

  cat > "$dir/Sources/SharedC/SharedC.swift" <<EOF
import CSharedC

public enum SharedCInfo {
    public static var major: Int { Int(shared_c_version()) }
}
EOF

  commit_and_tag "$dir" "$major.0.0"
}

for major in 1 2; do make_shared_c "$major"; done

echo "Fixtures ready in $ROOT"
git -C "$ROOT/Shared" tag
git -C "$ROOT/SharedC" tag
