# Swift Package Registry Reference Server

A minimal, in-memory reference implementation of the Swift Package Registry service
(per [SE-0292]) built with Vapor. It is intended to be exercised end-to-end with 
`swift package-registry publish` and the Swift Package Manager registry client.

## What's implemented

- `PUT /{scope}/{name}/{version}`: publish a release (multipart/form-data, synchronous 201)
- `GET /{scope}/{name}` (+ `.json`): list releases, with `Link: latest-version` and `?page=N` pagination
- `GET /{scope}/{name}/{version}` (+ `.json`): release info, including `resources[]` and `metadata`
- `GET /{scope}/{name}/{version}/Package.swift`: manifest, with `?swift-version=X.Y` support and alternate links
- `GET /{scope}/{name}/{version}.zip`: source archive with `Digest: sha-256=…`
- `GET /identifiers?url=…`: URL → identifier lookup
- `POST /users`: create an account (unauthenticated) with a password or a server-minted token
- `POST /login`: validate credentials for SwiftPM's `login` subcommand (HTTP Basic or Bearer)

This implementation does not implement signatures, async `202 Accepted` publishing, or mirrors.

## Running the server

### 1. Generate a self-signed TLS certificate

```bash
./scripts/generate-cert.sh
```

This writes `certs/cert.pem` and `certs/key.pem` (gitignored).

### 2. Trust the certificate

Swift Package Manager will refuse to talk to an untrusted host, so the
self-signed certificate must be added to the platform trust store.

**macOS:**

```bash
security add-trusted-cert -d -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db \
  certs/cert.pem
```

**Linux (Debian/Ubuntu):** files must end in `.crt`.

```bash
sudo cp certs/cert.pem /usr/local/share/ca-certificates/localhost-registry.crt
sudo update-ca-certificates
```

**Linux (Fedora/RHEL/CentOS):**

```bash
sudo cp certs/cert.pem /etc/pki/ca-trust/source/anchors/localhost-registry.pem
sudo update-ca-trust
```

### 3. Run

```bash
swift run PackageRegistryServer
```

If `certs/cert.pem` and `certs/key.pem` are present, the server binds to
`https://localhost:8000`. Otherwise it falls back to Vapor's default bind.

## Publishing the HelloWorld fixture

```bash
cd Fixtures/HelloWorld
swift package-registry set https://localhost:8000
swift package-registry publish exampleregistry.HelloWorld 1.0.0 \
  --url https://localhost:8000
```

Then exercise the retrieval endpoints:

```bash
curl -sH 'Accept: application/vnd.swift.registry.v1+json' \
  https://localhost:8000/exampleregistry/HelloWorld | jq
curl -sH 'Accept: application/vnd.swift.registry.v1+json' \
  https://localhost:8000/exampleregistry/HelloWorld/1.0.0 | jq
curl -sH 'Accept: application/vnd.swift.registry.v1+swift' \
  https://localhost:8000/exampleregistry/HelloWorld/1.0.0/Package.swift
curl -sH 'Accept: application/vnd.swift.registry.v1+zip' \
  https://localhost:8000/exampleregistry/HelloWorld/1.0.0.zip -o HelloWorld.zip
unzip -l HelloWorld.zip
```

## Running the tests

```bash
swift test
```

[SE-0292]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md

## Authentication

The registry associates a single credential with an email address — nothing
else is stored about a user. Passwords are kept as bcrypt hashes and tokens as
the SHA-256 of the plaintext, so no secret is ever persisted in the clear.

### Create an account

`POST /users` takes a JSON body. Include a `password` to create an HTTP Basic
account:

```bash
curl -skX POST https://localhost:8000/users \
  -d '{"email": "harry@hogwarts.com", "password": "ginny!"}'
# → 201 {"email":"harry@hogwarts.com"}
```

Omit `password` to mint a token account. The plaintext token is returned once —
persist it, because only its hash is stored:

```bash
curl -skX POST https://localhost:8000/users \
  -d '{"email": "harry@hogwarts.com"}'
# → 201 {"email":"harry@hogwarts.com","token":"kR8f…QeE"}
```

Registration rejects a malformed or duplicate email (`400`/`409`) and an empty
`password` (`400`).

### Log in

`POST /login` implements the SwiftPM registry login API: `200` on success,
`401` on invalid or missing credentials, and `501` for an authentication method
the registry does not support. It accepts both schemes:

```bash
# HTTP Basic (email:password)
swift package-registry login https://localhost:8000/login \
  --username harry@hogwarts.com --password ginny!

# Bearer token
swift package-registry login https://localhost:8000/login --token kR8f…QeE
```

Equivalently with curl:

```bash
curl -skX POST https://localhost:8000/login -u 'harry@hogwarts.com:ginny!'   # → 200
curl -skX POST https://localhost:8000/login -H 'Authorization: Bearer kR8f…QeE'  # → 200
```
