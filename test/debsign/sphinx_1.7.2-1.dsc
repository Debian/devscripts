Format: 3.0 (quilt)
Source: sphinx
Binary: python-sphinx, python3-sphinx, sphinx-common, sphinx-doc, libjs-sphinxdoc
Architecture: all
Version: 1.7.2-1
Maintainer: Debian Python Modules Team <python-modules-team@lists.alioth.debian.org>
Uploaders: Dmitry Shachnev <mitya57@debian.org>, Chris Lamb <lamby@debian.org>
Homepage: http://sphinx-doc.org/
Standards-Version: 4.1.4
Vcs-Browser: https://salsa.debian.org/python-team/modules/sphinx
Vcs-Git: https://salsa.debian.org/python-team/modules/sphinx.git
Testsuite: autopkgtest
Testsuite-Triggers: dvipng, gir1.2-webkit2-4.0, graphviz, imagemagick-6.q16, librsvg2-bin, python-enum34, python-html5lib, python-mock, python-pygments, python-pytest, python-sphinxcontrib.websupport, python-sqlalchemy, python-whoosh, python-xapian, python3-gi, python3-html5lib, python3-mock, python3-pygments, python3-pytest, python3-sphinxcontrib.websupport, python3-sqlalchemy, python3-whoosh, python3-xapian, texinfo, texlive-fonts-recommended, texlive-latex-extra, texlive-luatex, texlive-xetex, xauth, xvfb
Build-Depends: debhelper (>= 11)
Build-Depends-Indep: dh-python, dh-strip-nondeterminism, dpkg-dev (>= 1.17.14), python-all (>= 2.6.6-4~), python3-all (>= 3.3.3-1~), python3-lib2to3, python-six (>= 1.5), python3-six (>= 1.5), python-setuptools (>= 0.6c5-1~), python3-setuptools, python-docutils (>= 0.11), python3-docutils (>= 0.11), python-pygments (>= 2.1.1), python3-pygments (>= 2.1.1), python-jinja2 (>= 2.3), python3-jinja2 (>= 2.3), python-pytest, python3-pytest, python-mock, python3-mock, python-babel (>= 1.3), python3-babel (>= 1.3), python-alabaster (>= 0.7), python3-alabaster (>= 0.7), python-imagesize, python3-imagesize, python-requests (>= 2.4.0), python3-requests (>= 2.4.0), python-html5lib, python3-html5lib, python-enum34, python-typing, python-packaging, python3-packaging, python3-sphinxcontrib.websupport <!nodoc>, libjs-jquery (>= 1.4), libjs-underscore, texlive-latex-recommended, texlive-latex-extra, texlive-fonts-recommended, texinfo, texlive-luatex, texlive-xetex, dvipng, graphviz, imagemagick-6.q16, librsvg2-bin, perl
Package-List:
 libjs-sphinxdoc deb javascript optional arch=all
 python-sphinx deb python optional arch=all
 python3-sphinx deb python optional arch=all
 sphinx-common deb python optional arch=all
 sphinx-doc deb doc optional arch=all profile=!nodoc
Checksums-Sha1:
 1d1fa6954ae216cd44ea52dfc67063f26939c8f5 4719536 sphinx_1.7.2.orig.tar.gz
 facfa686a3a0bc98c269e16e66427f96e00889ad 34268 sphinx_1.7.2-1.debian.tar.xz
Checksums-Sha256:
 5a1c9a0fec678c24b9a2f5afba240c04668edb7f45c67ce2ed008996b3f21ae2 4719536 sphinx_1.7.2.orig.tar.gz
 a6a825914b19cfdbc22df858b0cecc497765dad2058deae20a88a6a2f9d57d24 34268 sphinx_1.7.2-1.debian.tar.xz
Files:
 21a08e994e6a289ed14eecefde2b4f2f 4719536 sphinx_1.7.2.orig.tar.gz
 e147e2afa47e7e58d1288ad8818c3de0 34268 sphinx_1.7.2-1.debian.tar.xz
