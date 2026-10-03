#!/usr/bin/env python3
# Serves the files devices download during setup and local upgrades:
# setup_device.sh and mynode_rootfs_<device>.tar.gz from the given directory
import http.server
import re
import sys

ALLOWED_PATH = re.compile(r"^/(setup_device\.sh|mynode_rootfs_[a-z0-9]+\.tar\.gz)$")

class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        if not ALLOWED_PATH.match(self.path.split("?", 1)[0]):
            self.send_error(404)
            return None
        return super().send_head()

def main():
    bind_address, port, directory = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    handler = lambda *args, **kwargs: Handler(*args, directory=directory, **kwargs)
    http.server.ThreadingHTTPServer((bind_address, port), handler).serve_forever()

if __name__ == "__main__":
    main()
