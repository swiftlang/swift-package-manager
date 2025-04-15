#!/bin/sh

executable="$(swift build --package-path /build -c release --show-bin-path)/binary-artifact-audit"
echo "$*"
objdump="$1"
shift
subcommand="$1"
shift

echo exec "$executable" "$subcommand" --objdump "$objdump" $@
exec "$executable" "$subcommand" --objdump "$objdump" $@

