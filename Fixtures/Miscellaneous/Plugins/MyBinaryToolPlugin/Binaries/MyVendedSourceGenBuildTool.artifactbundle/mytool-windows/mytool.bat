@echo off

set verbose=false
IF NOT "%1"=="" (
    IF "%1"=="--verbose" (
        SET verbose=true
        SHIFT
    )
)

set input=%1
set output=%2
shift
shift


if "%verbose%" == "true" (
    echo "[mytool-windows] '%input%' '%output%'"
)
@echo on
echo f | xcopy.exe /f "%input%" "%output%"