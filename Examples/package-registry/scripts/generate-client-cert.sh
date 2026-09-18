#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $(basename "$0") <email>" >&2
  exit 1
fi

EMAIL="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$PROJECT_DIR/certs"

mkdir -p "$CERT_DIR"

openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout "$CERT_DIR/client-key.pem" \
  -out "$CERT_DIR/client.pem" \
  -subj "/CN=$EMAIL/emailAddress=$EMAIL" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=clientAuth"

echo "Generated $CERT_DIR/client.pem and $CERT_DIR/client-key.pem for $EMAIL"
echo
echo "Register $EMAIL with the registry, then authenticate with the certificate:"
echo
echo "  curl -skX POST https://localhost:8000/login \\"
echo "    --cert $CERT_DIR/client.pem \\"
echo "    --key $CERT_DIR/client-key.pem"
