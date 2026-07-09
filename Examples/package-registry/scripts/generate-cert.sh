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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$PROJECT_DIR/certs"

mkdir -p "$CERT_DIR"

openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout "$CERT_DIR/key.pem" \
  -out "$CERT_DIR/cert.pem" \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

echo "Generated $CERT_DIR/cert.pem and $CERT_DIR/key.pem"
echo
echo "SwiftPM refuses untrusted hosts. Trust the certificate:"
echo

case "$(uname -s)" in
  Darwin)
    echo "  security add-trusted-cert -d -r trustRoot \\"
    echo "    -k ~/Library/Keychains/login.keychain-db \\"
    echo "    $CERT_DIR/cert.pem"
    ;;
  Linux)
    if command -v update-ca-certificates >/dev/null 2>&1; then
      echo "  # Debian/Ubuntu (the file must end in .crt)"
      echo "  sudo cp $CERT_DIR/cert.pem /usr/local/share/ca-certificates/localhost-registry.crt"
      echo "  sudo update-ca-certificates"
    elif command -v update-ca-trust >/dev/null 2>&1; then
      echo "  # Fedora/RHEL/CentOS"
      echo "  sudo cp $CERT_DIR/cert.pem /etc/pki/ca-trust/source/anchors/localhost-registry.pem"
      echo "  sudo update-ca-trust"
    else
      echo "  Add $CERT_DIR/cert.pem to your distribution's system trust store."
    fi
    ;;
  *)
    echo "  Add $CERT_DIR/cert.pem to your platform's system trust store."
    ;;
esac
