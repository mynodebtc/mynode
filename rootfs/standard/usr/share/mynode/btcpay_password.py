#!/usr/bin/env python3

# Creates, checks and resets the BTCPay Server administrator login (see post_btcpayserver.sh and
# change_btcpay_password() in device_info.py). Passwords are read from stdin so they stay out of
# the command line and the environment.
#
# Usage, with the password on stdin:
#   set   - create the administrator with that password, and print who owns the account:
#           "mynode" when this created it, "user" when an administrator already existed
#   check - exit 0 if that password is still the account's, 1 if it is not, 2 if that cannot be
#           determined (no account, or BTCPay's database is not reachable)
#   reset - give the MyNode administrator that password, without needing the current one
#
# "set" uses BTCPay's own API, which accepts an administrator with no login only while no
# administrator exists - the window this closes. "check" and "reset" work on the password hash in
# BTCPay's database, so neither needs a login: BTCPay only accepts Basic authentication for the
# first five minutes of an account's life, and API keys cannot be created after that without one.

import base64
import hashlib
import hmac
import json
import os
import struct
import subprocess
import sys
import urllib.error
import urllib.request

API = "http://127.0.0.1:49392/api/v1"
LOGIN = "admin@mynode.local"
DATABASE = "btcpayservermainnet"
TIMEOUT = 30

UNDETERMINED = 2

# ASP.NET Core Identity's PBKDF2 format (version 3): a 0x01 marker, then the PRF, the iteration
# count and the salt length as big-endian uint32s, then the salt and the subkey. Every parameter
# is in the hash, so Identity reads back whatever is written here, and a hash BTCPay wrote can be
# checked without knowing which settings it used.
IDENTITY_FORMAT_MARKER = 0x01
IDENTITY_PRFS = {0: "sha1", 1: "sha256", 2: "sha512"}
PRF_HMAC_SHA512 = 2
PBKDF2_ITERATIONS = 100000
PBKDF2_SALT_BYTES = 16
PBKDF2_SUBKEY_BYTES = 32


def identity_password_hash(password):
    salt = os.urandom(PBKDF2_SALT_BYTES)
    subkey = hashlib.pbkdf2_hmac(
        IDENTITY_PRFS[PRF_HMAC_SHA512],
        password.encode(),
        salt,
        PBKDF2_ITERATIONS,
        dklen=PBKDF2_SUBKEY_BYTES,
    )
    blob = (
        struct.pack("B", IDENTITY_FORMAT_MARKER)
        + struct.pack(">III", PRF_HMAC_SHA512, PBKDF2_ITERATIONS, len(salt))
        + salt
        + subkey
    )
    return base64.b64encode(blob).decode()


def identity_password_matches(password, password_hash):
    blob = base64.b64decode(password_hash)
    if not blob or blob[0] != IDENTITY_FORMAT_MARKER:
        raise ValueError("unexpected password hash format")
    prf, iterations, salt_length = struct.unpack(">III", blob[1:13])
    if prf not in IDENTITY_PRFS:
        raise ValueError("unexpected password hash function")
    salt = blob[13:13 + salt_length]
    subkey = blob[13 + salt_length:]
    computed = hashlib.pbkdf2_hmac(
        IDENTITY_PRFS[prf], password.encode(), salt, iterations, dklen=len(subkey)
    )
    return hmac.compare_digest(computed, subkey)


def psql(statement, value=None):
    """
    Run one statement against BTCPay's database, the way btcpay-admin.sh does. A value is passed
    as a psql variable, which only works for a statement fed in on stdin - not with "-c".
    """
    container = subprocess.run(
        ["docker", "ps", "-a", "-q", "-f", "name=postgres_1"],
        capture_output=True,
        universal_newlines=True,
    ).stdout.strip()
    if not container:
        return None

    command = ["docker", "exec", "-i", container, "psql", "-U", "postgres", "-d", DATABASE,
               "-t", "-A", "--no-psqlrc", "-v", "ON_ERROR_STOP=1", "-f", "-"]
    if value is not None:
        command[-2:-2] = ["--set=value=" + value]
    return subprocess.run(
        command, input=statement + "\n", capture_output=True, universal_newlines=True
    )


def read_password_hash():
    result = psql(
        'SELECT "PasswordHash" FROM "AspNetUsers" '
        "WHERE \"NormalizedEmail\" = upper('{}');".format(LOGIN)
    )
    if result is None or result.returncode != 0:
        return None
    return result.stdout.strip() or None


def call(path, data=None):
    headers = {}
    if data is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(data).encode()
    request = urllib.request.Request(
        API + path, data=data, headers=headers, method="POST" if data else "GET"
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except OSError as e:
        # BTCPay is not answering at all
        return 0, str(e).encode()


def set_password(password):
    code, payload = call(
        "/users", data={"email": LOGIN, "password": password, "isAdministrator": True}
    )
    if code in (200, 201):
        print("mynode")
        return 0
    if code in (401, 403):
        print("user")
        return 0

    sys.stderr.write(
        "could not create the BTCPay administrator (HTTP {}): {}\n".format(
            code, payload.decode("utf-8", "replace")[:500]
        )
    )
    return 1


def check(password):
    password_hash = read_password_hash()
    if password_hash is None:
        return UNDETERMINED
    try:
        return 0 if identity_password_matches(password, password_hash) else 1
    except ValueError as e:
        sys.stderr.write("could not check the BTCPay password: {}\n".format(e))
        return UNDETERMINED


def reset_password(password):
    result = psql(
        'UPDATE "AspNetUsers" SET "PasswordHash" = :\'value\' '
        "WHERE \"NormalizedEmail\" = upper('{}');".format(LOGIN),
        identity_password_hash(password),
    )
    if result is None:
        sys.stderr.write("BTCPay's postgres container is not running\n")
        return 1
    if result.returncode != 0:
        sys.stderr.write("BTCPay password reset failed: {}\n".format(result.stderr.strip()))
        return 1
    if result.stdout.strip() != "UPDATE 1":
        sys.stderr.write(
            "BTCPay password reset did not match one account: {}\n".format(result.stdout.strip())
        )
        return 1
    return 0


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("set", "check", "reset"):
        raise SystemExit("usage: btcpay_password.py set|check|reset  (password on stdin)")

    password = sys.stdin.read().strip()
    if not password:
        raise SystemExit("no password given on stdin")

    if sys.argv[1] == "set":
        return set_password(password)
    if sys.argv[1] == "check":
        return check(password)
    return reset_password(password)


if __name__ == "__main__":
    sys.exit(main())
