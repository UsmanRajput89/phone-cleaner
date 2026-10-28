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
if 'FileProvider' not in s:
    provider = (
        '        <provider android:name="androidx.core.content.FileProvider" '
        'android:authorities="${applicationId}.fileprovider" '
        'android:exported="false" android:grantUriPermissions="true">\n'
        '            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" '
        'android:resource="@xml/file_paths"/>\n'
        '        </provider>\n'
    )
    s = s.replace('</application>', provider + '    </application>', 1)
open(manifest, 'w').write(s)

import os
os.makedirs('android/app/src/main/res/xml', exist_ok=True)
open('android/app/src/main/res/xml/file_paths.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<paths>\n'
    '    <external-path name="all" path="."/>\n'
    '</paths>\n'
)

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

# --- Pin the signing key: every build must be signed with android_overlay/debug.keystore
# (a different key per build makes Android refuse to install updates).
import shutil
shutil.copy('android_overlay/debug.keystore', 'android/app/debug.keystore')
kts = 'android/app/build.gradle.kts'
groovy = 'android/app/build.gradle'
if os.path.exists(kts):
    g = open(kts).read()
    block = (
        'android {\n'
        '    signingConfigs {\n'
        '        getByName("debug") {\n'
        '            storeFile = file("debug.keystore")\n'
        '            storePassword = "android"\n'
        '            keyAlias = "androiddebugkey"\n'
        '            keyPassword = "android"\n'
        '        }\n'
        '    }\n'
    )
    path = kts
elif os.path.exists(groovy):
    g = open(groovy).read()
    block = (
        'android {\n'
        '    signingConfigs {\n'
        '        debug {\n'
        '            storeFile file("debug.keystore")\n'
        '            storePassword "android"\n'
        '            keyAlias "androiddebugkey"\n'
        '            keyPassword "android"\n'
        '        }\n'
        '    }\n'
    )
    path = groovy
else:
    print('no app build.gradle(.kts) found', file=sys.stderr)
    sys.exit(1)
if 'debug.keystore' not in g:
    if 'android {' not in g:
        print('android { block not found in', path, file=sys.stderr)
        sys.exit(1)
    g = g.replace('android {\n', block, 1)
    open(path, 'w').write(g)
print('pinned signing key in', path)
