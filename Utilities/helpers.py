#!/usr/bin/env python3
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

import datetime
import logging
import subprocess
import sys
import os
import errno

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
    logging.info("executing command >>> %s", ' '.join(cmd))
    try:
        subprocess.check_call(cmd, cwd=cwd)
    except subprocess.CalledProcessError as cpe:
        logging.debug("executing command >>> %s", ' '.join(cmd))
        logging.error(
            "Process failure: %s\n[---- START OUTPUT ----]\n%s\n[---- END OUTPUT ----]",
            str(cpe),
            cpe.output,
        )
        raise cpe

def call_output(cmd, cwd=None, stderr=False, verbose=False):
    """Calls a subprocess for its return data."""
    stderr = subprocess.STDOUT if stderr else False
    logging.info(' '.join(cmd))
    try:
        return subprocess.check_output(cmd, cwd=cwd, stderr=stderr, universal_newlines=True).strip()
    except subprocess.CalledProcessError as cpe:
        logging.debug(' '.join(cmd))
        logging.error(
            "%s\n[---- START OUTPUT ----]\n%s\n[---- END OUTPUT ----]",
            str(cpe),
            cpe.output,
        )
        raise cpe
