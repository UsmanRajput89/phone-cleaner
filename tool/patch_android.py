#!/usr/bin/env python3
"""Patches the generated Flutter android/ folder: permissions, app label and the
native bridge (MainActivity.kt). Run from the repo root after `flutter create`."""
import glob
import re
import sys

manifest = 'android/app/src/main/AndroidManifest.xml'
s = open(manifest).read()

perms = (
    '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n'
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n'
    '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n'
)
if 'MANAGE_EXTERNAL_STORAGE' not in s:
    s = s.replace('<application', perms + '    <application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Phone Cleaner"', s, count=1)
if 'requestLegacyExternalStorage' not in s:
    s = s.replace('<application', '<application android:requestLegacyExternalStorage="true"', 1)
open(manifest, 'w').write(s)

candidates = [c for c in glob.glob('android/app/src/main/**/MainActivity.*', recursive=True)
              if c.endswith('.kt')]
if not candidates:
    print('MainActivity.kt not found', file=sys.stderr)
    sys.exit(1)
target = candidates[0]
existing = open(target).read()
m = re.search(r'^package\s+([\w.]+)', existing, re.M)
if not m:
    print('package line not found in', target, file=sys.stderr)
    sys.exit(1)
tmpl = open('android_overlay/MainActivity.kt').read().replace('PACKAGE_PLACEHOLDER', m.group(1))
open(target, 'w').write(tmpl)
print('patched', manifest, 'and', target, 'package', m.group(1))
