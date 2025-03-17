#!/usr/bin/env python3
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

import contextlib
import enum
import errno
import logging
import os
import pathlib
import subprocess
import typing as t


@contextlib.contextmanager
def change_directory(directory: pathlib.Path) -> t.Iterator[pathlib.Path]:
    current_directory = pathlib.Path.cwd()
    logging.info("Current directory is %s", current_directory)
    logging.info("Changing directory to: %s", directory)
    os.chdir(directory)

    try:
        yield directory
    finally:
        logging.debug("Chaning directory back to %s", current_directory)
        os.chdir(current_directory)


class Configuration(str, enum.Enum):
    DEBUG = "debug"
    RELEASE = "release"

    def __str__(self) -> str:
        return self.value


def symlink_force(source, destination):
    try:
        os.symlink(source, destination)
    except OSError as e:
        if e.errno == errno.EEXIST:
            os.remove(destination)
            os.symlink(source, destination)


def mkdir_p(path):
    """Create the given directory, if it does not exist."""
    try:
        os.makedirs(path)
    except OSError as e:
        # Ignore EEXIST, which may occur during a race condition.
        if e.errno != errno.EEXIST:
            raise


def call(cmd, cwd=None, verbose=False):
    """Calls a subprocess."""
    cwd = cwd or pathlib.Path.cwd()
    logging.info("executing command >>> %r with cwd %s", " ".join([str(c) for c in cmd]), cwd)
    try:
        subprocess.check_call(cmd, cwd=cwd)
    except subprocess.CalledProcessError as cpe:
        logging.debug("executing command >>> %r with cwd %s", " ".join([str(c) for c in cmd]), cwd)
        logging.error(
            "\n".join([
                "Process failure with return code %d: %s",
                "[---- START stdout ----]",
                "%s",
                "[---- END stdout ----]",
                "[---- START stderr ----]",
                "%s",
                "[---- END stderr ----]",
                "[---- START OUTPUT ----]",
                "%s",
                "[---- END OUTPUT ----]",
            ]),
            cpe.returncode,
            str(cpe),
            cpe.stdout,
            cpe.stderr,
            cpe.output,
        )
        raise cpe


def call_output(cmd, cwd=None, stderr=False, verbose=False):
    """Calls a subprocess for its return data."""
    stderr = subprocess.STDOUT if stderr else False
    cwd = cwd or pathlib.Path.cwd()
    logging.info("executing command >>> %r with cwd %s", " ".join([str(c) for c in cmd]), cwd)
    try:
        return subprocess.check_output(
            cmd,
            cwd=cwd,
            stderr=stderr,
            universal_newlines=True,
        ).strip()
    except subprocess.CalledProcessError as cpe:
        logging.debug("executing command >>> %r with cwd %s", " ".join([str(c) for c in cmd]), cwd)
        logging.error(
            "\n".join([
                "Process failure with return code %d: %s",
                "[---- START stdout ----]",
                "%s",
                "[---- END stdout ----]",
                "[---- START stderr ----]",
                "%s",
                "[---- END stderr ----]",
                "[---- START OUTPUT ----]",
                "%s",
                "[---- END OUTPUT ----]",
            ]),
            cpe.returncode,
            str(cpe),
            cpe.stdout,
            cpe.stderr,
            cpe.output,
        )
        raise cpe
