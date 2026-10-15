#!/usr/bin/env python3
"""Check the packaged daemon with launchd-style argv and working directory."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
with (app / "Contents/Library/LaunchDaemons/com.mrcroxx.click.daemon.plist").open("rb") as stream:
    service = plistlib.load(stream)
program = service["BundleProgram"]
arguments = service["ProgramArguments"]
assert arguments == [program], "Daemon requires explicit launch arguments"
executable = (app / program).resolve()
assert executable.is_relative_to(app) and executable.is_file()
# --check validates the enclosing app signature without opening HID or XPC.
subprocess.run(arguments + ["--check"], executable=str(executable), cwd="/", check=True)
