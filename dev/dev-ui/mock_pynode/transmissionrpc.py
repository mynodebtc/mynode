"""Stub for the (ancient) transmissionrpc package, imported at mynode.py top
level but only used on the QuickSync download page, where it is wrapped in
try/except. Raising here produces the real 'Waiting on download client to
start...' UI."""


class TransmissionError(Exception):
    pass


class Client(object):
    def __init__(self, *args, **kwargs):
        raise TransmissionError("mocked: no transmission daemon in UI dev mode")
