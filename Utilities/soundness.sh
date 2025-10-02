#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2022 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -eu
set -o pipefail

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function replace_acceptable_years() {
    # this needs to replace all acceptable forms with 'YEARS'
    sed -e 's/20[12][0123456789]-20[12][0123456789]/YEARS/' -e 's/20[12][0123456789]/YEARS/'
}

printf "=> Checking for unacceptable language... "
# This greps for unacceptable terminology. The square bracket[s] are so that
# "git grep" doesn't find the lines that greps :).
unacceptable_terms=(
    -e blacklis[t]
    -e whitelis[t]
    -e slav[e]
    -e sanit[y]
)

# We have to exclude the code of conduct as it gives examples of unacceptable language.
if git grep --color=never -i "${unacceptable_terms[@]}" -- . > /dev/null; then
    printf "\033[0;31mUnacceptable language found.\033[0m\n"
    git grep -i "${unacceptable_terms[@]}" -- .
    exit 1
fi
printf "\033[0;32mokay.\033[0m\n"

printf "=> Checking format... \n"
git diff --name-only | grep -v ".swiftpm" | grep ".swift" | while read changed_file; do
  printf "  * checking ${changed_file}... "
  before=$(cat ${changed_file})
  swiftformat $changed_file > /dev/null 2>&1
  after=$(cat ${changed_file})

  if [[ "$before" != "$after" ]]; then
    printf "\033[0;31mformatting issues!\033[0m\n"
    git --no-pager diff ${changed_file}
    exit 1
  else
    printf "\033[0;32mokay.\033[0m\n"
  fi
done

printf "=> Checking license headers... \n"
tmp=$(mktemp /tmp/.swift-package-manager-soundness_XXXXXX)

for language in swift-or-c bash python; do
  printf "   * $language... "
  declare -a matching_files
  declare -a exceptions
  exceptions=( )
  matching_files=( -name '*' )
  case "$language" in
      swift-or-c)
        exceptions=(
          -name "Package.swift"
          -o -path "./Sources/PackageSigning/embedded_resources.swift"
          -o -path "./Examples/*"
          -o -path "./Fixtures/*"
          -o -path "./IntegrationTests/*"
          -o -path "./Tests/ExtraTests/*"
          -o -path "./Tests/PackageLoadingTests/Inputs/*"
        )
        matching_files=( -name '*.swift' -o -name '*.c' -o -name '*.h' )
        cat > "$tmp" <<"EOF"
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) YEARS Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
EOF
        ;;
      bash)
        exceptions=( -path "./Examples/*" -o -path "./Fixtures/*" -o -path "./IntegrationTests/*" -o -path "*/.build/*" )
        matching_files=( -name '*.sh' )
        cat > "$tmp" <<"EOF"
#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) YEARS Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##
EOF
      ;;
      python)
        exceptions=( -path "./Examples/*" -o -path "./Fixtures/*" -o -path "./IntegrationTests/*"  -o -path "*/.build/*" )
        matching_files=( -name '*.py' )
        cat > "$tmp" <<"EOF"
#!/usr/bin/env python3
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) YEARS Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##
EOF
      ;;
    *)
      echo >&2 "ERROR: unknown language '$language'"
      ;;
  esac

  expected_lines=$(cat "$tmp" | wc -l)
  expected_sha=$(cat "$tmp" | shasum)

  (
    cd "$here/.."
    {
        find . \
            \( \! -path './.build/*' -a \
            \( "${matching_files[@]}" \) -a \
            \( \! \( "${exceptions[@]}" \) \) \)

    } | while read line; do
      if [[ "$(cat "$line" | replace_acceptable_years | head -n $expected_lines | shasum)" != "$expected_sha" ]]; then
        printf "\033[0;31mmissing headers in file '$line'!\033[0m\n"
        diff -u <(cat "$line" | replace_acceptable_years | head -n $expected_lines) "$tmp"
        exit 1
      fi
    done
    printf "\033[0;32mokay.\033[0m\n"
  )
done

rm "$tmp"
