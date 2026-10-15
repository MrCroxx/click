#!/usr/bin/env python3
"""Verify the distributable app, volume icon and installation shortcut."""
import re
import tempfile
from pathlib import Path
from create_macos_dmg import run, read_plist, detach_image
import sys

image = Path(sys.argv[1]).resolve()
run('/usr/bin/hdiutil', 'verify', str(image))
mount = Path(tempfile.mkdtemp(prefix='click-dmg-verify-'))
device = None
try:
    attached = read_plist(run, 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(image))
    device = next(e['dev-entry'] for e in attached['system-entities'] if re.fullmatch(r'/dev/disk\d+', e.get('dev-entry', '')))
    app = mount / 'Click.app'
    assert (mount / 'Applications').is_symlink()
    assert (mount / 'Applications').readlink() == Path('/Applications')
    assert (mount / '.VolumeIcon.icns').read_bytes() == (app / 'Contents/Resources/Click.icns').read_bytes()
    assert run('/usr/bin/xcrun', 'GetFileInfo', '-aC', str(mount), capture=True).strip() == b'1'
    assert run('/usr/bin/xcrun', 'GetFileInfo', '-aC', str(image), capture=True).strip() == b'1'
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    run('/usr/bin/codesign', '--verify', str(image))
    print('Verified DMG: signed app, matching volume icon, file icon and Applications shortcut.')
finally:
    if device:
        detach_image(device)
        mount.rmdir()
