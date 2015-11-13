#!/usr/bin/python
import BaseHTTPServer
import SimpleHTTPServer
import logging

class GetHandler(SimpleHTTPServer.SimpleHTTPRequestHandler):
    def do_GET(self):
	logging.error(self.headers)
        SimpleHTTPServer.SimpleHTTPRequestHandler.do_GET(self)

def test():
    Handler = GetHandler
    httpd = BaseHTTPServer.HTTPServer(('', 0), Handler)

    sa = httpd.socket.getsockname()
    with open('port', 'w') as f:
        f.write(str(sa[1]))

    httpd.serve_forever()

if __name__ == '__main__':
    test()
