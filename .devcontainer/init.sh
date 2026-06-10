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

# Calculates absolute paths for the git repo root and current workspace

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

GIT_COMMON_DIR=$(git rev-parse --git-common-dir)
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR="$PWD/$GIT_COMMON_DIR" ;;
esac

env_file="${SCRIPT_DIR}/.env"
# Ensure the paths are absolute for Docker mounting
echo "GIT_REPO=$(realpath "$GIT_COMMON_DIR")" > "${env_file}"
echo "WORKSPACE_DIR=$(realpath "$PWD")" >> "${env_file}"
