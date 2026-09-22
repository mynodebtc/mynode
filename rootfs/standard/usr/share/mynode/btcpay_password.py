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
#   reset - give a server administrator that password, without needing the current one. Takes the
#           account's email; with none, the sole administrator, failing if there are several
#
# One command takes no password and reads nothing from stdin:
#   admins - print the email of every server administrator, one per line
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
SERVER_ADMIN_ROLE = "SERVERADMIN"
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


def psql(statement, value=None, password_hash=None):
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
    if password_hash is not None:
        command[-2:-2] = ["--set=hash=" + password_hash]
    return subprocess.run(
        command, input=statement + "\n", capture_output=True, universal_newlines=True
    )


def read_password_hash(login=LOGIN):
    result = psql(
        'SELECT "PasswordHash" FROM "AspNetUsers" WHERE "NormalizedEmail" = upper(:\'value\');',
        login,
    )
    if result is None or result.returncode != 0:
        return None
    return result.stdout.strip() or None


def read_admins():
    """Every account holding BTCPay's ServerAdmin role, by the email it logs in with."""
    result = psql(
        'SELECT u."Email" FROM "AspNetUsers" u '
        'JOIN "AspNetUserRoles" ur ON ur."UserId" = u."Id" '
        'JOIN "AspNetRoles" r ON r."Id" = ur."RoleId" '
        "WHERE r.\"NormalizedName\" = '{}' ORDER BY u.\"Email\";".format(SERVER_ADMIN_ROLE)
    )
    if result is None or result.returncode != 0:
        return None
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


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
    login = resolve_admin(None)
    if login is None:
        return UNDETERMINED
    password_hash = read_password_hash(login)
    if password_hash is None:
        return UNDETERMINED
    try:
        return 0 if identity_password_matches(password, password_hash) else 1
    except ValueError as e:
        sys.stderr.write("could not check the BTCPay password: {}\n".format(e))
        return UNDETERMINED


def resolve_admin(login):
    """
    The account "reset" and "check" act on: the one named, else the account MyNode created, else
    the only administrator there is. Never a guess between several - the wrong one would lock the
    owner out of their own account.
    """
    admins = read_admins()
    if admins is None:
        sys.stderr.write("could not read BTCPay's administrator accounts\n")
        return None
    if not admins:
        sys.stderr.write("BTCPay has no administrator account\n")
        return None
    if login:
        for admin in admins:
            if admin.lower() == login.lower():
                return admin
        sys.stderr.write("{} is not a BTCPay administrator\n".format(login))
        return None
    for admin in admins:
        if admin.lower() == LOGIN:
            return admin
    if len(admins) > 1:
        sys.stderr.write(
            "BTCPay has several administrators ({}) - name the one to reset\n".format(
                ", ".join(admins)
            )
        )
        return None
    return admins[0]


def reset_password(password, login=None):
    login = resolve_admin(login)
    if login is None:
        return 1
    result = psql(
        'UPDATE "AspNetUsers" SET "PasswordHash" = :\'hash\' '
        'WHERE "NormalizedEmail" = upper(:\'value\');',
        login,
        password_hash=identity_password_hash(password),
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
    print(login)
    return 0


def list_admins():
    admins = read_admins()
    if admins is None:
        return UNDETERMINED
    for admin in admins:
        print(admin)
    return 0


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command not in ("set", "check", "reset", "admins") or len(sys.argv) > 3:
        raise SystemExit(
            "usage: btcpay_password.py set|check|reset [email]  (password on stdin)\n"
            "       btcpay_password.py admins"
        )

    if command == "admins":
        return list_admins()

    password = sys.stdin.read().strip()
    if not password:
        raise SystemExit("no password given on stdin")

    if command == "set":
        return set_password(password)
    if command == "check":
        return check(password)
    return reset_password(password, sys.argv[2] if len(sys.argv) == 3 else None)


if __name__ == "__main__":
    sys.exit(main())
