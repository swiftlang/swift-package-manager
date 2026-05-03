#!/usr/bin/env bash
#
# Drive `swift-package-resolver-bench` through `hyperfine` across a matrix
# of topologies, sizes, and simulated I/O latencies, then emit a Markdown
# table suitable for pasting into a PR comment.
#
# Usage:
#   Utilities/bench-resolver.sh                  # write report to stdout
#   Utilities/bench-resolver.sh --label before   # tag the report (e.g. before/after)
#   Utilities/bench-resolver.sh --out report.md  # also write to file
#
# Requires: hyperfine, jq, swift.

set -euo pipefail

label=""
out=""
sizes=(10 30)
latencies=(5 30)
topologies=(wide-unversioned wide-revision deep-unversioned deep-revision mixed)
warmup=2
runs=5

while [[ $# -gt 0 ]]; do
    case "$1" in
        --label) label="$2"; shift 2;;
        --out) out="$2"; shift 2;;
        --sizes) IFS=',' read -ra sizes <<< "$2"; shift 2;;
        --latencies) IFS=',' read -ra latencies <<< "$2"; shift 2;;
        --topologies) IFS=',' read -ra topologies <<< "$2"; shift 2;;
        --warmup) warmup="$2"; shift 2;;
        --runs) runs="$2"; shift 2;;
        -h|--help)
            sed -n '2,11p' "$0"
            exit 0;;
        *) echo "unknown flag: $1" >&2; exit 2;;
    esac
done

for tool in hyperfine jq swift; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' is not on PATH" >&2
        exit 1
    fi
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

echo "==> Building swift-package-resolver-bench (release)" >&2
swift build -c release --product swift-package-resolver-bench >&2

bin="$repo_root/.build/release/swift-package-resolver-bench"
if [[ ! -x "$bin" ]]; then
    echo "error: built binary not found at $bin" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Header
{
    if [[ -n "$label" ]]; then
        echo "### Resolver benchmark — \`$label\`"
    else
        echo "### Resolver benchmark"
    fi
    echo
    echo "Hardware: \`$(uname -smr)\` · hyperfine warmup=$warmup runs=$runs · per-fetch simulated latency in ms"
    echo
    echo "| topology | size | latency (ms) | mean (ms) | stddev (ms) | min (ms) | max (ms) |"
    echo "|---|---:|---:|---:|---:|---:|---:|"
} > "$tmp_dir/report.md"

for topo in "${topologies[@]}"; do
    for size in "${sizes[@]}"; do
        for lat in "${latencies[@]}"; do
            json="$tmp_dir/${topo}-s${size}-l${lat}.json"
            echo "==> hyperfine topology=$topo size=$size latency=${lat}ms" >&2
            hyperfine \
                --warmup "$warmup" \
                --runs "$runs" \
                --export-json "$json" \
                --command-name "${topo}/${size}/${lat}ms" \
                -- \
                "'$bin' --topology $topo --size $size --latency-ms $lat --quiet" \
                >/dev/null

            mean_s=$(jq -r '.results[0].mean' "$json")
            stddev_s=$(jq -r '.results[0].stddev' "$json")
            min_s=$(jq -r '.results[0].min' "$json")
            max_s=$(jq -r '.results[0].max' "$json")
            printf "| %s | %d | %d | %.1f | %.1f | %.1f | %.1f |\n" \
                "$topo" "$size" "$lat" \
                "$(echo "$mean_s * 1000" | bc -l)" \
                "$(echo "$stddev_s * 1000" | bc -l)" \
                "$(echo "$min_s * 1000" | bc -l)" \
                "$(echo "$max_s * 1000" | bc -l)" \
                >> "$tmp_dir/report.md"
        done
    done
done

cat "$tmp_dir/report.md"
if [[ -n "$out" ]]; then
    cp "$tmp_dir/report.md" "$out"
    echo "==> wrote $out" >&2
fi
