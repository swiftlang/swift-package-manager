#!/bin/sh

set -eu

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: $0 <swift-build> <llvm-objcopy> <custom-libs-dir> [size-in-mib]" >&2
  exit 2
fi

swift_build=$1
llvm_objcopy=$2
custom_libs_dir=$3
size_mib=${4:-8}
work_dir=${TMPDIR:-/tmp}/swiftpm-embedded-resource-benchmark

rm -rf "$work_dir"
mkdir -p "$work_dir/ByteArray/Sources/Benchmark" "$work_dir/ObjectFile/Sources/Benchmark"

dd if=/dev/urandom of="$work_dir/payload.bin" bs=1048576 count="$size_mib" 2>/dev/null
cp "$work_dir/payload.bin" "$work_dir/ByteArray/Sources/Benchmark/payload.bin"
cp "$work_dir/payload.bin" "$work_dir/ObjectFile/Sources/Benchmark/payload.bin"

cat > "$work_dir/ByteArray/Package.swift" <<'EOF'
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "EmbeddedResourceByteArrayBenchmark",
    targets: [
        .executableTarget(
            name: "Benchmark",
            resources: [.embedInCode("payload.bin")]
        ),
    ]
)
EOF

cat > "$work_dir/ObjectFile/Package.swift" <<'EOF'
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "EmbeddedResourceObjectFileBenchmark",
    targets: [
        .executableTarget(
            name: "Benchmark",
            resources: [
                .embedInCode("payload.bin", representation: .objectFile),
            ]
        ),
    ]
)
EOF

for package in ByteArray ObjectFile; do
  cat > "$work_dir/$package/Sources/Benchmark/main.swift" <<'EOF'
var checksum: UInt64 = 0
for byte in PackageResources.payload_bin {
    checksum &+= UInt64(byte)
}
print("\(PackageResources.payload_bin.count):\(checksum)")
EOF
done

measure() {
  name=$1
  shift
  if [ "$(uname -s)" = Darwin ]; then
    /usr/bin/time -l -o "$work_dir/$name.time" "$@" \
      > "$work_dir/$name.stdout" 2> "$work_dir/$name.stderr"
  else
    /usr/bin/time -v -o "$work_dir/$name.time" "$@" \
      > "$work_dir/$name.stdout" 2> "$work_dir/$name.stderr"
  fi
}

build_package() {
  package=$1
  if measure "build-$package" env \
      SWIFTPM_CUSTOM_LIBS_DIR="$custom_libs_dir" \
      LLVM_OBJCOPY="$llvm_objcopy" \
      "$swift_build" \
      --build-system native \
      --configuration release \
      --package-path "$work_dir/$package" \
      --scratch-path "$work_dir/$package/.build"; then
    echo succeeded > "$work_dir/build-$package.status"
  else
    echo failed > "$work_dir/build-$package.status"
  fi
}

build_package ByteArray
build_package ObjectFile

for package in ByteArray ObjectFile; do
  executable=$(find "$work_dir/$package/.build" -type f -path '*/release/Benchmark' -perm +111 | head -1)
  if [ -n "$executable" ]; then
    measure "run-$package" "$executable"
  fi
done

echo "payload bytes: $(wc -c < "$work_dir/payload.bin" | tr -d ' ')"
echo
for package in ByteArray ObjectFile; do
  generated_source=$(find "$work_dir/$package/.build" -name embedded_resources.swift -type f | head -1)
  executable=$(find "$work_dir/$package/.build" -type f -path '*/release/Benchmark' -perm +111 | head -1)
  echo "$package"
  echo "  build status:           $(cat "$work_dir/build-$package.status")"
  if [ -n "$generated_source" ]; then
    echo "  generated source bytes: $(wc -c < "$generated_source" | tr -d ' ')"
  fi
  if [ -n "$executable" ]; then
    echo "  executable bytes:       $(wc -c < "$executable" | tr -d ' ')"
    echo "  output:                 $(cat "$work_dir/run-$package.stdout")"
  fi
  echo "  build metrics:"
  sed 's/^/    /' "$work_dir/build-$package.time"
  if [ -f "$work_dir/run-$package.time" ]; then
    echo "  runtime metrics:"
    sed 's/^/    /' "$work_dir/run-$package.time"
  fi
  echo
done

echo "complete logs: $work_dir"
