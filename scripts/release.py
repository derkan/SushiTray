#!/usr/bin/env python3
"""Build, commit and push a versioned release; GitHub Actions publishes it."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None).stdout


def main():
    version = os.environ.get('VERSION', '')
    branch = os.environ.get('RELEASE_BRANCH', 'main')
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        sys.exit('Usage: make release VERSION=X.Y.Z')
    run('git', 'check-ref-format', f'refs/heads/{branch}')
    if run('git', 'status', '--porcelain', '--untracked-files=no', capture=True).strip():
        sys.exit('Commit tracked changes before releasing (or use a clean worktree).')
    notes = Path(f'release-notes/{version}.md')
    if not notes.is_file() or not notes.read_text().strip():
        sys.exit(f'Write and commit {notes} before releasing.')
    run('git', 'ls-files', '--error-unmatch', str(notes))
    tag = f'v{version}'
    if run('git', 'tag', '--list', tag, capture=True).strip():
        sys.exit(f'Tag {tag} already exists.')
    run('git', 'fetch', 'origin', branch, '--tags')
    run('git', 'merge-base', '--is-ancestor', f'origin/{branch}', 'HEAD')
    if run('git', 'tag', '--list', tag, capture=True).strip():
        sys.exit(f'Tag {tag} already exists on origin.')
    path = Path('SushiTray/Info.plist')
    original = path.read_bytes()
    info = plistlib.loads(original)
    current = info['CFBundleShortVersionString']
    if tuple(map(int, version.split('.'))) <= tuple(map(int, current.split('.'))):
        sys.exit(f'New version must be greater than {current}.')
    committed = False
    try:
        run('/usr/libexec/PlistBuddy', '-c', f'Set :CFBundleShortVersionString {version}', str(path))
        run('/usr/libexec/PlistBuddy', '-c', f'Set :CFBundleVersion {int(info["CFBundleVersion"]) + 1}', str(path))
        run('make', 'test')
        run('make', 'dist')
        run('git', 'add', '--', str(path))
        run('git', 'commit', '-m', f'chore: bump version to {version}')
        committed = True
        run('git', 'tag', '-a', tag, '-m', f'SushiTray {version}')
        run('git', 'push', '--atomic', 'origin', f'HEAD:refs/heads/{branch}', f'refs/tags/{tag}')
    finally:
        if not committed:
            path.write_bytes(original)
    print(f'{tag} pushed. GitHub Actions will build and publish the release using {notes}.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
