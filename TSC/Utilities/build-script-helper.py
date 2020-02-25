#!/usr/bin/env python

"""
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
"""

from __future__ import print_function

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import subprocess
import sys
import errno

def note(message):
    print("--- %s: note: %s" % (os.path.basename(sys.argv[0]), message))
    sys.stdout.flush()

def error(message):
    print("--- %s: error: %s" % (os.path.basename(sys.argv[0]), message))
    sys.stdout.flush()
    raise SystemExit(1)

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

def main():
    parser = argparse.ArgumentParser(description="""
        This script will build a TSC using CMake.
        """)
    subparsers = parser.add_subparsers(dest='command')

    # build
    parser_build = subparsers.add_parser("build", help="builds TSC using CMake")
    parser_build.set_defaults(func=build)
    add_build_args(parser_build)

    args = parser.parse_args()
    args.func = args.func or build
    args.func(args)

# -----------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------

def add_global_args(parser):
    """Configures the parser with the arguments necessary for all actions."""
    parser.add_argument(
        "--build-dir",
        help="path where products will be built [%(default)s]",
        default=".build",
        metavar="PATH")
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="whether to print verbose output")
    parser.add_argument(
        "--reconfigure",
        action="store_true",
        help="whether to always reconfigure cmake")

def add_build_args(parser):
    """Configures the parser with the arguments necessary for build-related actions."""
    add_global_args(parser)
    parser.add_argument(
        "--swiftc-path",
        help="path to the swift compiler",
        metavar="PATH")
    parser.add_argument(
        '--cmake-path',
        metavar='PATH',
        help='path to the cmake binary to use for building')
    parser.add_argument(
        '--ninja-path',
        metavar='PATH',
        help='path to the ninja binary to use for building with CMake')

def parse_global_args(args):
    """Parses and cleans arguments necessary for all actions."""
    args.build_dir = os.path.abspath(args.build_dir)
    args.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    if platform.system() == 'Darwin':
        args.sysroot = call_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], verbose=args.verbose)
    else:
        args.sysroot = None

def parse_build_args(args):
    """Parses and cleans arguments necessary for build-related actions."""
    parse_global_args(args)

    args.swiftc_path = get_swiftc_path(args)
    args.cmake_path = get_cmake_path(args)
    args.ninja_path = get_ninja_path(args)

def get_swiftc_path(args):
    """Returns the path to the Swift compiler."""
    if args.swiftc_path:
        swiftc_path = os.path.abspath(args.swiftc_path)
    elif os.getenv("SWIFT_EXEC"):
        swiftc_path = os.path.realpath(os.getenv("SWIFT_EXEC"))
    elif platform.system() == 'Darwin':
        swiftc_path = call_output(
            ["xcrun", "--find", "swiftc"],
            stderr=subprocess.PIPE,
            verbose=args.verbose
        )
    else:
        swiftc_path = call_output(["which", "swiftc"], verbose=args.verbose)

    if os.path.basename(swiftc_path) == 'swift':
        swiftc_path = swiftc_path + 'c'

    return swiftc_path

def get_cmake_path(args):
    """Returns the path to CMake."""
    if args.cmake_path:
        return os.path.abspath(args.cmake_path)
    elif platform.system() == 'Darwin':
        return call_output(
            ["xcrun", "--find", "cmake"],
            stderr=subprocess.PIPE,
            verbose=args.verbose
        )
    else:
        return call_output(["which", "cmake"], verbose=args.verbose)

def get_ninja_path(args):
    """Returns the path to Ninja."""
    if args.ninja_path:
        return os.path.abspath(args.ninja_path)
    elif platform.system() == 'Darwin':
        return call_output(
            ["xcrun", "--find", "ninja"],
            stderr=subprocess.PIPE,
            verbose=args.verbose
        )
    else:
        return call_output(["which", "ninja"], verbose=args.verbose)

# -----------------------------------------------------------
# Actions
# -----------------------------------------------------------

def build(args):
    parse_build_args(args)
    build_tsc(args)

# -----------------------------------------------------------
# Build functions
# -----------------------------------------------------------

def build_with_cmake(args, cmake_args, source_path, build_dir):
    """Runs CMake if needed, then builds with Ninja."""
    cache_path = os.path.join(build_dir, "CMakeCache.txt")
    if args.reconfigure or not os.path.isfile(cache_path) or not args.swiftc_path in open(cache_path).read():
        swift_flags = ""
        if args.sysroot:
            swift_flags = "-sdk %s" % args.sysroot

        cmd = [
            args.cmake_path, "-G", "Ninja",
            "-DCMAKE_MAKE_PROGRAM=%s" % args.ninja_path,
            "-DCMAKE_BUILD_TYPE:=Debug",
            "-DCMAKE_Swift_FLAGS=" + swift_flags,
            "-DCMAKE_Swift_COMPILER:=%s" % (args.swiftc_path),
        ] + cmake_args + [source_path]

        if args.verbose:
            print(' '.join(cmd))

        mkdir_p(build_dir)
        call(cmd, cwd=build_dir, verbose=True)

    # Build.
    ninja_cmd = [args.ninja_path]

    if args.verbose:
        ninja_cmd.append("-v")

    call(ninja_cmd, cwd=build_dir, verbose=args.verbose)

def build_tsc(args):
    cmake_flags = []
    if platform.system() == 'Darwin':
        cmake_flags.append("-DCMAKE_C_FLAGS=-target x86_64-apple-macosx10.10")
        cmake_flags.append("-DCMAKE_OSX_DEPLOYMENT_TARGET=10.10")

    build_with_cmake(args, cmake_flags, args.project_root, args.build_dir)

if __name__ == '__main__':
    main()
