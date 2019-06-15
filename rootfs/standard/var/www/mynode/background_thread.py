import threading
import time
import os

class BackgroundThread(threading.Thread):
 
    def __init__(self, run_function, rate=30):
        threading.Thread.__init__(self)
 
        # The shutdown_flag is a threading.Event object that
        # indicates whether the thread should be terminated.
        self.shutdown_flag = threading.Event()
        self.run_function = run_function
        self.rate = rate
        self.pid = 0
 
        # ... Other thread setup code here ...
 
    def run(self):
        print('Thread #%s started' % self.ident)

        self.pid = os.getpid()
 
        while not self.shutdown_flag.is_set():
            self.run_function()
            time.sleep(self.rate)
 
        # ... Clean shutdown code here ...
        print('Thread #%s stopped' % self.ident)