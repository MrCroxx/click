#!/usr/bin/env python3
"""Create a DMG with system tools, including the app and mounted-volume icons."""
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def run(*args, capture=False):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE if capture else None).stdout


def read_plist(run_command, *args):
    return plistlib.loads(run_command('/usr/bin/hdiutil', *args, '-plist', capture=True))


def detach_image(device, run_command=run, wait=time.sleep):
    for attempt in range(16):
        try:
            run_command('/usr/bin/hdiutil', 'detach', device, *(['-force'] if attempt == 15 else []))
            return
        except subprocess.CalledProcessError as error:
            images = read_plist(run_command, 'info')['images']
            if not any(entity.get('dev-entry') == device
                       for image in images for entity in image['system-entities']):
                return
            if error.returncode != 16 or attempt == 15:
                raise
            delay = min(attempt + 1, 5)
            print(f'DMG {device} is busy; retrying detach in {delay}s.', file=sys.stderr)
            wait(delay)


def create_dmg(staging, destination, icon, name, run_command=run, wait=time.sleep):
    temporary = Path(tempfile.mkdtemp(prefix='click-dmg-'))
    writable = temporary / 'writable.dmg'
    mount = temporary / 'volume'
    may_be_attached = False
    device = None
    try:
        mount.mkdir()
        run_command('/usr/bin/hdiutil', 'create', '-format', 'UDRW', '-fs', 'HFS+',
                    '-volname', name, '-srcfolder', str(staging), str(writable))
        may_be_attached = True
        attached = read_plist(run_command, 'attach', '-nobrowse', '-mountpoint', str(mount), str(writable))
        device = next((e['dev-entry'] for e in attached['system-entities']
                       if re.fullmatch(r'/dev/disk\d+', e.get('dev-entry', ''))), None)
        if not device:
            raise RuntimeError('Cannot identify the attached DMG device')
        try:
            shutil.copyfile(icon, mount / '.VolumeIcon.icns')
            run_command('/usr/bin/xcrun', 'SetFile', '-a', 'C', str(mount))
        finally:
            # Exceptions retain their context if setting the icon and ejecting both fail.
            detach_image(device, run_command, wait)
            may_be_attached = False
        run_command('/usr/bin/hdiutil', 'convert', str(writable), '-ov', '-format', 'UDZO', '-o', str(destination))
        run_command('/usr/bin/swift', str(Path(__file__).with_name('set-macos-icon.swift')),
                    str(icon), str(destination))
    finally:
        # Never recursively remove a directory that might contain a mounted filesystem.
        if may_be_attached:
            print(f'DMG {device or writable} may still be attached; preserving {temporary}', file=sys.stderr)
        else:
            shutil.rmtree(temporary)


if __name__ == '__main__':
    if len(sys.argv) != 5:
        raise SystemExit('Usage: create_macos_dmg.py staging destination.dmg icon.icns volume-name')
    create_dmg(*sys.argv[1:])
