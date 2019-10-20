#!/usr/bin/python3
import http.server
from http.server import SimpleHTTPRequestHandler
import logging


class GetHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        logging.error(self.headers)
        SimpleHTTPRequestHandler.do_GET(self)


def test():
    Handler = GetHandler
    httpd = http.server.HTTPServer(('', 0), Handler)

    sa = httpd.socket.getsockname()
    with open('port', 'w') as f:
        f.write(str(sa[1]))

    httpd.serve_forever()


if __name__ == '__main__':
    test()
