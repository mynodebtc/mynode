import socket
import json


def get_from_electrum(method, params=[]):
    params = [params] if type(params) is not list else params
    s = socket.create_connection(('127.0.0.1', 50001))
    s.send(json.dumps({"id": 0, "method": method, "params": params}).encode() + b'\n')
    return json.loads(s.recv(99999)[:-1].decode())