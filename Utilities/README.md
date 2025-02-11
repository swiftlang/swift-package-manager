# Windows Self-Hosted Test

Steps to be confirmed

```
${REPO_ROOT_PATH} = git rev-parse --show-toplevel
${TARGET_PATH} = "C:\source"

docker pull swiftlang/swift:nightly-main-windowsservercore-1809
docker run --rm --volume "${REPO_ROOT_PATH}:${TARGET_PATH}" --interactive --tty --name "win_test" --workdir "${TARGET_PATH}" swiftlang/swift:nightly-main-windowsservercore-1809 python3 .\Utilities\build-using-self
```