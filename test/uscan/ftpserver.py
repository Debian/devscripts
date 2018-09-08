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

    logging.basicConfig(filename='info.log', level=logging.INFO)
    # logging.basicConfig(filename='debuag.log', level=logging.DEBUG)

    ftpserver = FTPServer(("127.0.0.1", 0), handler)
    sa = ftpserver.socket.getsockname()
    with open('port', 'w') as f:
        f.write(str(sa[1]))
    ftpserver.serve_forever()


if __name__ == '__main__':
    test()
