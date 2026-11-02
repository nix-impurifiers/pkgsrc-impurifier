#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Run native pkgsrc transactions using writable local package copies."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    if os.geteuid() != 0:
        raise ValueError('native pkgsrc requires root')
    for key in ('ROOT', 'DESTDIR', 'PKG_DESTDIR'):
        if os.environ.get(key, '/') not in ('', '/'):
            raise ValueError('native pkgsrc requires the live host root')
    args = sys.argv[1:]
    status = 0
    if args and args[0] == 'install' and len(args) > 1:
        with tempfile.TemporaryDirectory(prefix='pkgsrc-impurifier-') as directory:
            copies = []
            for index, value in enumerate(args[1:]):
                source = Path(value).resolve(strict=True)
                if not source.is_file() or not source.name.endswith('.tgz'):
                    raise ValueError('install requires native .tgz archive paths')
                target = Path(directory) / str(index) / source.name
                target.parent.mkdir()
                shutil.copyfile(source, target)
                copies.append(str(target))
            status = subprocess.run(['pkg_add', '-U', *copies], stdin=subprocess.DEVNULL).returncode
    elif args and args[0] == 'remove' and len(args) > 1:
        if any(not re.fullmatch(r'[a-z0-9][a-z0-9+._-]*', value) for value in args[1:]):
            raise ValueError('remove requires package identities')
        status = subprocess.run(['pkg_delete', *args[1:]], stdin=subprocess.DEVNULL).returncode
    elif args != ['reconcile']:
        raise ValueError('use install ARCHIVE...; remove PACKAGE...; or reconcile')
    if status:
        return status
    activation = subprocess.run(['/usr/sbin/pkgsrc-impurifier-activate']).returncode
    return status or activation


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print('pkgsrc-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
