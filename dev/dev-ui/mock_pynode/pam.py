"""Mock `pam` module: authenticates the web UI login against the DEV_PASSWORD
environment variable (default 'bolt', the myNode factory password) instead of
the OS admin user. The real login flow in user_management.py (rate limiting,
session handling) runs unchanged."""
import os


class _MockPam(object):
    def authenticate(self, username, password, **kwargs):
        expected = os.environ.get("DEV_PASSWORD", "bolt")
        return password == expected


def pam():
    return _MockPam()
