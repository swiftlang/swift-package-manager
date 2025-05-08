# Binary Artifact Auditing Tool

This tool allows checking that a binary static library artifact will be compatible with any supported Linux Swift deployment platform.

It is intended to be used in conjunction with the provided `Dockerfile` as follows:
```
$ docker build -t my-tag .
$ docker run --rm my-tag <validate-local/validate-remote> <artifact-path/artifact-url>
```

## Operation

The tool uses the installed `llvm-objdump` to inspect the static library as well as the local libc and any C runtime libraries and/or object files to
determine if any symbols aren't defined.

## Known Supported Platforms

| Docker Image          | libc.so version |
| --------------------- | --------------- |
| 6.0-fedora39          | GNU libc 2.38   |
| 6.0-rhel-ubi9-slim    | GNU libc 2.34   |
| 6.0-amazonlinux2-slim | GNU libc 2.26   |
| 6.0-bookworm          | GNU libc 2.36   |
| 6.0-focal-slim        | GNU libc 2.31   |
