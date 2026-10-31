#!/usr/bin/env python3
"""Run offline resolver and shell syntax checks in a disposable Linux container."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'python:3.14-slim@sha256:cd89c30eda26ee911a4611b18680086e0ea42e6f5f8cbe653d07fa7958c9cec8'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=ROOT,
                        help='Separate source tree for baseline/mutation testing')
    parser.add_argument('--image', default=IMAGE,
                        help='Linux image with Python 3, APT and Bash (default pinned)')
    args = parser.parse_args()
    command = ['docker', 'run', '--rm', '--pull=never', '--network=none', '--read-only',
               '--cap-drop=ALL', '--security-opt=no-new-privileges',
               '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m',
               '--mount', f'type=bind,src={ROOT},dst=/tests-source,readonly',
               '--mount', f'type=bind,src={args.source_root.resolve()},dst=/source,readonly',
               '-e', 'MYNODE_SOURCE_ROOT=/source', args.image]
    result = subprocess.run(command + ['python3', '-B',
                                      '/tests-source/tests/test_kernel_upgrade.py'])
    syntax = subprocess.run(command + ['bash', '-ec',
        'bash -n /source/rootfs/standard/usr/bin/mynode_upgrade_os_packages.sh; '
        'bash -n /source/rootfs/standard/usr/bin/mynode_post_upgrade.sh; '
        'bash -n /source/setup/setup_device.sh'])
    print(f'Resolver exit={result.returncode}; Linux Bash syntax exit={syntax.returncode}', flush=True)
    return result.returncode or syntax.returncode


if __name__ == '__main__':
    raise SystemExit(main())
