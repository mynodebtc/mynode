#!/usr/bin/env python3
"""Real offline APT regression tests; see README.kernel-upgrade.md."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("MYNODE_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
FIXTURES = Path(__file__).resolve().parent / "fixtures/kernel-upgrade"
SCRIPTS = (
    "rootfs/standard/usr/bin/mynode_upgrade_os_packages.sh",
    "rootfs/standard/usr/bin/mynode_post_upgrade.sh",
)
IMAGE = "linux-image-6.1.0-54-amd64"


def source_command(path):
    """Extract the actual upgrade command and its option assignment, not a flag copy.

    Only these isolated lines are evaluated. Never run appliance setup or sources.
    Fail closed if source structure changes rather than silently testing stale flags.
    """
    lines = path.read_text().splitlines()
    commands = [line.strip() for line in lines
                if re.match(r"\s*\$TORIFY apt-get\b", line)
                and re.search(r"\bupgrade\s*$", line)]
    if len(commands) != 1:
        raise AssertionError(f"Expected one APT upgrade command in {path}: {commands}")
    assignments = [line for line in lines if line.startswith('APT_OPTIONS=')]
    if "$APT_OPTIONS" in commands[0] and len(assignments) != 1:
        raise AssertionError(f"Missing/ambiguous APT_OPTIONS in {path}")
    return '\n'.join(['TORIFY=""'] + assignments + [commands[0]])


class KernelUpgrade(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ("apt-get", "bash"):
            if not shutil.which(tool):
                raise RuntimeError(f"{tool} required; use the documented Linux container")
        metadata = json.loads((FIXTURES / "provenance.json").read_text())
        actual = hashlib.sha256((FIXTURES / "Packages").read_bytes()).hexdigest()
        if actual != metadata['fixture_sha256']:
            raise AssertionError("Official package fixture checksum mismatch")
        print(subprocess.check_output(['apt-get', '--version'], text=True).splitlines()[0])

    def resolve(self, command, held=False):
        with tempfile.TemporaryDirectory(prefix="mynode-apt-") as directory:
            root = Path(directory)
            for name in ('lists/partial', 'archives/partial', 'sourceparts',
                         'preferencesparts', 'apt.conf.d', 'log'):
                (root / name).mkdir(parents=True)
            status = (FIXTURES / 'status').read_text()
            if held:
                status = status.replace('Status: install ok installed',
                                        'Status: hold ok installed', 1)
            (root / 'status').write_text(status)
            (root / 'lists/offline.invalid_debian_dists_fixture_main_binary-amd64_Packages').write_bytes(
                (FIXTURES / 'Packages').read_bytes() + b'\n' +
                (FIXTURES / 'synthetic-Packages').read_bytes())
            (root / 'sources.list').write_text(
                'deb [trusted=yes arch=amd64] http://offline.invalid/debian fixture main\n')
            config = root / 'apt.conf'
            config.write_text(f'''
Dir "{root}";
Dir::State "{root}";
Dir::State::status "{root}/status";
Dir::State::lists "{root}/lists";
Dir::State::extended_states "{root}/extended_states";
Dir::Cache "{root}";
Dir::Cache::archives "{root}/archives";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
Dir::Etc "{root}";
Dir::Etc::main "/dev/null";
Dir::Etc::parts "{root}/apt.conf.d";
Dir::Etc::sourcelist "{root}/sources.list";
Dir::Etc::sourceparts "{root}/sourceparts";
Dir::Etc::preferences "{root}/preferences";
Dir::Etc::preferencesparts "{root}/preferencesparts";
Dir::Log "{root}/log";
APT::Architecture "amd64";
APT::Architectures {{ "amd64"; }};
APT::Install-Recommends "true";
APT::Install-Suggests "false";
Acquire::Languages "none";
Debug::NoLocking "true";
''')
            # Simulation is injected by the harness, all upgrade policy comes from source.
            shell = 'set -eu\napt-get() { command apt-get --simulate "$@"; }\n' + command
            result = subprocess.run(['bash', '-c', shell], text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    env={**os.environ, 'APT_CONFIG': str(config),
                                         'LC_ALL': 'C', 'LANG': 'C'})
            print(f"\nCOMMAND:\n{command}\nHELD={held}\n{result.stdout}", flush=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            return result.stdout

    def assert_no_removals(self, output):
        self.assertNotRegex(output, r'(?m)^Remv ')
        self.assertIn('0 to remove', output)
        self.assertNotRegex(output, r'(?m)^Inst fixture-application ')

    def test_source_commands_install_new_kernel_without_removing_packages(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                output = self.resolve(source_command(ROOT / script))
                self.assertRegex(output, rf'(?m)^Inst {IMAGE} \(6\.1\.190-1 ')
                self.assertRegex(output, r'(?m)^Inst linux-image-amd64 \[6\.1\.187-1\] \(6\.1\.190-1 ')
                self.assert_no_removals(output)

    def test_explicit_kernel_hold_is_respected_by_each_path(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                output = self.resolve(source_command(ROOT / script), held=True)
                self.assertNotRegex(output, r'(?m)^Inst linux-image-')
                self.assertIn('linux-image-amd64', output)
                self.assert_no_removals(output)

    def test_plain_upgrade_negative_control(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                command = source_command(ROOT / script).replace('--with-new-pkgs', '')
                output = self.resolve(command)
                self.assertNotRegex(output, r'(?m)^Inst linux-image-')
                self.assertIn('linux-image-amd64', output)
                self.assert_no_removals(output)


if __name__ == '__main__':
    unittest.main(verbosity=2)
