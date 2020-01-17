"""
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
"""

import subprocess
import sys
import os
import errno

def note(message):
    print("--- %s: note: %s" % (os.path.basename(sys.argv[0]), message))
    sys.stdout.flush()

def error(message):
    print("--- %s: error: %s" % (os.path.basename(sys.argv[0]), message))
    sys.stdout.flush()
    raise SystemExit(1)

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
    if verbose:
        print(' '.join(cmd))
    try:
        subprocess.check_call(cmd, cwd=cwd)
    except Exception as e:
        if not verbose:
            print(' '.join(cmd))
        error(str(e))

def call_output(cmd, cwd=None, stderr=False, verbose=False):
    """Calls a subprocess for its return data."""
    if verbose:
        print(' '.join(cmd))
    try:
        return subprocess.check_output(cmd, cwd=cwd, stderr=stderr, universal_newlines=True).strip()
    except Exception as e:
        if not verbose:
            print(' '.join(cmd))
        error(str(e))
