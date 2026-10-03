import os
import socket

# MYNODE_FILE_SERVER_IP overrides the detected address, e.g. when a VPN holds the default route
ip = os.environ.get("MYNODE_FILE_SERVER_IP")
if not ip:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    ip = s.getsockname()[0]
    s.close()
print(ip)
