#!/usr/bin/env python3
"""Linux root-only fixture tests. Run only in a disposable container, never a node.

No database/service is started. chown and kernel UID/GID permission checks are real.
The full prestart entrypoint runs with synthetic config; only the marked Mempool
section of startup runs (the rest of startup changes unrelated system state).
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

SOURCE = Path(__file__).resolve().parents[1]
ROOT = Path('/mnt/hdd/mynode/mempool')
OUTSIDE = Path('/mnt/outside')
PRE = SOURCE / 'rootfs/standard/usr/bin/service_scripts/pre_mempool.sh'
STARTUP = SOURCE / 'rootfs/standard/usr/bin/mynode_startup.sh'
APP = (1004, 1004)


def owner(path):
    st = path.lstat()
    return st.st_uid, st.st_gid


def access_as(path, uid, gid):
    # Fork and actually drop all supplementary groups and process credentials.
    pid = os.fork()
    if pid == 0:
        try:
            os.setgroups([])
            os.setgid(gid)
            os.setuid(uid)
            with path.open('r+') as stream:
                assert stream.read() == 'synthetic database\n'
                stream.write('')
            os._exit(0)
        except (OSError, AssertionError):
            os._exit(1)
    return os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]) == 0


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        for p in (ROOT, OUTSIDE):
            if p.is_symlink():
                p.unlink()
            elif p.exists():
                shutil.rmtree(p)
        ROOT.mkdir(parents=True)
        OUTSIDE.mkdir()
        share = Path('/usr/share/mynode')
        share.mkdir(parents=True, exist_ok=True)
        (share / 'mynode_config.sh').write_text('IS_RASPI=0\nIS_ARM64=1\n')
        (share / 'mynode_app_versions.sh').write_text('MEMPOOL_VERSION=v3.3.1\n')
        (share / 'mempool.env').write_text('VERSION=old\nBITCOIN_RPC_PASS=old\nMARIA_DB_IMAGE=old\n')
        shutil.copyfile(SOURCE / 'rootfs/standard/usr/share/mynode/mempool-docker-compose.yml', share / 'mempool-docker-compose.yml')
        settings = ROOT.parent / 'settings'
        settings.mkdir(exist_ok=True)
        (settings / '.btcrpcpw').write_text('synthetic-only')

    def run_script(self, entry):
        if entry == 'pre':
            command = ['bash', str(PRE)]
        else:
            text = STARTUP.read_text().split('# Setup Mempool\n', 1)[1].split('# Setup Netdata\n', 1)[0]
            command = ['bash', '-c', text]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def app_tree(self):
        (ROOT / 'data/nested').mkdir(parents=True)
        (ROOT / 'data/nested/cache with spaces').write_text('cache')
        (ROOT / 'extra').write_text('application')

    def assert_app(self):
        for p in [ROOT, ROOT / 'data', ROOT / 'data/nested', ROOT / 'data/nested/cache with spaces', ROOT / 'extra']:
            self.assertEqual(owner(p), APP, str(p))

    def test_fresh_and_missing_optional_directories(self):
        for entry in ('pre', 'startup'):
            with self.subTest(entry=entry):
                self.run_script(entry)
                self.assertEqual(owner(ROOT), APP)
                self.assertFalse((ROOT / 'mysql').exists())
                self.assertFalse((ROOT / 'data').exists())
                if entry == 'pre':
                    self.assertEqual(owner(ROOT / '.env'), APP)
                    self.assertIn('VERSION=v3.3.1', (ROOT / '.env').read_text())
                    self.assertIn('MARIA_DB_IMAGE=mariadb:10.9.3', (ROOT / '.env').read_text())

    def test_existing_database_owners_and_real_access(self):
        # 999 is one reported example, NOT a production ownership constant.
        for uid, gid in [(999, 999), (1234, 2345)]:
            for entry in ('pre', 'startup'):
                with self.subTest(uid=uid, gid=gid, entry=entry):
                    self.setUp()
                    self.app_tree()
                    db = ROOT / 'mysql/data'
                    db.mkdir(parents=True)
                    table = db / 'table.ibd'
                    table.write_text('synthetic database\n')
                    table.chmod(0o600)
                    db.chmod(0o700)
                    for p in (ROOT / 'mysql', db, table):
                        os.chown(p, uid, gid)
                    before = {str(p): (owner(p), p.stat().st_mode) for p in (ROOT / 'mysql', db, table)}
                    digest = hashlib.sha256(table.read_bytes()).hexdigest()
                    self.assertTrue(access_as(table, uid, gid), 'DB UID must have baseline access')
                    self.run_script(entry)
                    accessible = access_as(table, uid, gid)
                    print(f'{entry}: DB principal={uid}:{gid}, table owner={owner(table)}, read/write={accessible}', flush=True)
                    self.assertTrue(accessible, f'DB UID {uid}:{gid} lost real access')
                    self.assertEqual(before, {str(p): (owner(p), p.stat().st_mode) for p in (ROOT / 'mysql', db, table)})
                    self.assertEqual(hashlib.sha256(table.read_bytes()).hexdigest(), digest)
                    self.assert_app()
                    print(f'actual UID/GID {uid}:{gid}: read/write preserved via {entry}', flush=True)

    def test_missing_service_directory_fails(self):
        ROOT.rmdir()
        result = subprocess.run(['bash', str(PRE)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(ROOT.exists())

    def test_mysql_parent_without_data(self):
        (ROOT / 'mysql').mkdir()
        os.chown(ROOT / 'mysql', 1234, 2345)
        for entry in ('pre', 'startup'):
            self.run_script(entry)
            self.assertEqual(owner(ROOT / 'mysql'), (1234, 2345))
            self.assertFalse((ROOT / 'mysql/data').exists())

    def test_symlinks_not_followed(self):
        self.app_tree()
        target = OUTSIDE / 'file'
        target.write_text('outside')
        os.chown(target, 1234, 2345)
        os.chown(OUTSIDE, 1234, 2345)
        (ROOT / 'mysql').symlink_to(OUTSIDE, target_is_directory=True)
        (ROOT / 'data/directory-link').symlink_to(OUTSIDE, target_is_directory=True)
        (ROOT / 'data/file-link').symlink_to(target)
        (ROOT / 'data/dangling-link').symlink_to(OUTSIDE / 'missing')
        db_link_owner = owner(ROOT / 'mysql')
        for entry in ('pre', 'startup'):
            self.run_script(entry)
            self.assertEqual(owner(OUTSIDE), (1234, 2345))
            self.assertEqual(owner(target), (1234, 2345))
            self.assertEqual(target.read_text(), 'outside')
            self.assertEqual(owner(ROOT / 'mysql'), db_link_owner)
            for name in ('directory-link', 'file-link', 'dangling-link'):
                self.assertEqual(owner(ROOT / 'data' / name), APP)
            self.assert_app()

    def test_database_data_symlink_not_followed(self):
        (ROOT / 'mysql').mkdir()
        (ROOT / 'mysql/data').symlink_to(OUTSIDE, target_is_directory=True)
        target = OUTSIDE / 'table'
        target.write_text('outside')
        os.chown(target, 1234, 2345)
        os.chown(OUTSIDE, 1234, 2345)
        before = owner(ROOT / 'mysql/data')
        for entry in ('pre', 'startup'):
            self.run_script(entry)
            self.assertEqual(owner(ROOT / 'mysql/data'), before)
            self.assertEqual(owner(OUTSIDE), (1234, 2345))
            self.assertEqual(owner(target), (1234, 2345))

    def test_ownership_walk_root_symlink_not_followed(self):
        # Only the ownership section: prestart's earlier cp/sed deliberately
        # assumes the real service WorkingDirectory, not an arbitrary symlink.
        ROOT.rmdir()
        ROOT.symlink_to(OUTSIDE, target_is_directory=True)
        target = OUTSIDE / 'file'
        target.write_text('outside')
        os.chown(target, 1234, 2345)
        os.chown(OUTSIDE, 1234, 2345)
        self.run_script('startup')
        self.assertEqual(owner(OUTSIDE), (1234, 2345))
        self.assertEqual(owner(target), (1234, 2345))
        self.assertEqual(owner(ROOT), APP)

    def test_data_symlink_not_followed(self):
        (ROOT / 'data').symlink_to(OUTSIDE, target_is_directory=True)
        os.chown(OUTSIDE, 1234, 2345)
        for entry in ('pre', 'startup'):
            self.run_script(entry)
            self.assertEqual(owner(OUTSIDE), (1234, 2345))
            self.assertEqual(owner(ROOT / 'data'), APP)


if __name__ == '__main__':
    if sys.platform != 'linux' or os.geteuid() != 0 or os.environ.get('MYNODE_DISPOSABLE_TEST') != '1':
        sys.exit('Requires Linux root inside an explicitly disposable container (MYNODE_DISPOSABLE_TEST=1).')
    # These files must be on a container-only /etc tmpfs, not a host mount.
    Path('/etc/passwd').write_text('root:x:0:0:root:/root:/bin/bash\nmempool:x:1004:1004:fixture:/nonexistent:/bin/false\n')
    Path('/etc/group').write_text('root:x:0:\nmempool:x:1004:\n')
    unittest.main(verbosity=2)
