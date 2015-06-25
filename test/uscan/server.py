#!/usr/bin/python
import BaseHTTPServer
from SimpleHTTPServer import SimpleHTTPRequestHandler

def test():
    SimpleHTTPRequestHandler.protocol_version='HTTP/1.0'
    httpd = BaseHTTPServer.HTTPServer(('', 0), SimpleHTTPRequestHandler)

    sa = httpd.socket.getsockname()
    with open('port', 'w') as f:
        f.write(str(sa[1]))

    httpd.serve_forever()

if __name__ == '__main__':
    test()
