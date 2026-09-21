#!/usr/bin/env python3

# Reads and sets the password of the LNbits super user account. Run inside the LNbits container
# (see pre_lnbits.sh): the database file is owned by root, and the bcrypt LNbits hashes with is
# only in the image - under its virtualenv, so run it with /app/.venv/bin/python where that
# exists. The data folder is mounted at /app/data.
#
# Usage, with the password on stdin:
#   check - exit 0 if that password still works (or there is nothing to check), 1 if it does not
#   set   - give the account that password if it has none, and print who set the one it has

import sys
import sqlite3

try:
    # What LNbits hashes with from v1.3 on
    from bcrypt import checkpw, gensalt, hashpw

    def hash_password(password):
        return hashpw(password.encode(), gensalt()).decode()

    def verify_password(password, password_hash):
        return checkpw(password.encode(), password_hash.encode())

except ImportError:
    # Older LNbits used passlib, which produces and reads the same bcrypt hashes
    from passlib.context import CryptContext

    def _context():
        return CryptContext(schemes=["bcrypt"], deprecated="auto")

    def hash_password(password):
        return _context().hash(password)

    def verify_password(password, password_hash):
        return _context().verify(password, password_hash)


DATA_FOLDER = "/app/data/"
DATABASE = DATA_FOLDER + "database.sqlite3"


def read_super_user_id():
    # Written by LNbits on every start once the admin UI is enabled
    with open(DATA_FOLDER + ".super_user") as f:
        return f.read().strip()


def read_password_hash(super_user_id, read_only=True):
    if read_only:
        db = sqlite3.connect("file:" + DATABASE + "?mode=ro", uri=True)
    else:
        db = sqlite3.connect(DATABASE)
    row = db.execute(
        "SELECT password_hash FROM accounts WHERE id = ?", (super_user_id,)
    ).fetchone()
    return db, row


def check(password):
    try:
        super_user_id = read_super_user_id()
    except OSError:
        # LNbits has not run with the admin UI on, so there is no account to check against
        return 0

    db, row = read_password_hash(super_user_id)
    db.close()
    if not row or not row[0]:
        # No password set - pre_lnbits.sh sets one on the next start
        return 0

    return 0 if verify_password(password, row[0]) else 1


def set_password(password):
    super_user_id = read_super_user_id()
    db, row = read_password_hash(super_user_id, read_only=False)
    if row is None:
        raise SystemExit("LNbits super user account not found")

    if row[0]:
        # The account already has a password, so the user set it themselves
        print("user")
    else:
        # Clearing "env" as the provider is what closes the first install page
        db.execute(
            """
            UPDATE accounts
            SET username = COALESCE(NULLIF(username, ''), 'admin'),
                password_hash = ?,
                extra = json_set(COALESCE(NULLIF(extra, ''), '{}'), '$.provider', 'lnbits')
            WHERE id = ?
            """,
            (hash_password(password), super_user_id),
        )
        db.commit()
        print("mynode")
    db.close()
    return 0


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("check", "set"):
        raise SystemExit("usage: lnbits_password.py check|set  (password on stdin)")

    password = sys.stdin.read().strip()
    if not password:
        raise SystemExit("no password given on stdin")

    if sys.argv[1] == "check":
        return check(password)
    return set_password(password)


if __name__ == "__main__":
    sys.exit(main())
