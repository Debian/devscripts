#!/usr/bin/python3

import os
import logging
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer

def test():
    authorizer = DummyAuthorizer()
    authorizer.add_anonymous(os.getcwd())

    handler = FTPHandler
    handler.authorizer = authorizer

    logging.basicConfig(filename='log', level=logging.INFO)
    #logging.basicConfig(filename='log', level=logging.DEBUG)

    ftpserver = FTPServer(("127.0.0.1", 2121), handler)
    ftpserver.serve_forever()

if __name__ == '__main__':
    test()
