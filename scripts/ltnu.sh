#!/bin/sh

# Copyright 2017 Axel Beckert <abe@debian.org>.
# Licensed under the GNU GPL, version 2 or later.

set -e

if [ "${1}" = '-h' -o "${1}" = '--help' ]; then
    echo "${0} (Long Time No Upload) queries the public mirror of the
Ultimate Debian Database (UDD) for all uploads of packages by the
given uploader or maintainer and displays them ordered by the last
upload of that package, oldest uploads first.

The maintainer/uploader to query can be given either by setting
\$DEBEMAIL as environment variable or as single commandline parameter.

If a commandline parameter does not contain an \"@\", \"@debian.org\"
is appended, e.g. \"${0} abe\" queries for \"abe@debian.org\".

Exceptions are some shortcuts for common, long e-mail addresses. So
far implemented shortcuts:

* pkg-perl = pkg-perl-maintainers@lists.alioth.debian.org
* pkg-zsh  = pkg-zsh-devel@lists.alioth.debian.org
* pkg-gnustep = pkg-gnustep-maintainers@lists.alioth.debian.org
"
    exit 0
fi

if [ ! -x /usr/bin/psql ]; then
    echo "/usr/bin/psql not found or not executable" 1>&2
    echo "${0} requires a PostgreSQL client (psql) to be installed." 1>&2
    exit 2
fi

MAINT="${DEBEMAIL}"
if [ -n "${1}" ]; then
    if echo "${1}" | fgrep -q @; then
        MAINT="${1}"
    elif [ "${1}" = "pkg-perl" ]; then
        MAINT="pkg-perl-maintainers@lists.alioth.debian.org"
    elif [ "${1}" = "pkg-zsh" ]; then
        MAINT="pkg-zsh-devel@lists.alioth.debian.org"
    elif [ "${1}" = "pkg-gnustep" ]; then
        MAINT="pkg-gnustep-maintainers@lists.alioth.debian.org"
    elif [ "${1}" = "qa" ]; then
        MAINT="packages@qa.debian.org"
    else
        MAINT="${1}@debian.org"
    fi
fi

if [ -z "${MAINT}" ]; then
    echo "${0} requires either the environment variable \$DEBEMAIL to be set or a single parameter." 1>&2
    exit 1;
fi

if [ -z "${PAGER}" -o "${PAGER}" = "less" ]; then
    export PAGER="less -S"
fi

env PGPASSWORD=udd-mirror psql --host=udd-mirror.debian.net --user=udd-mirror udd --command="
select source,
       max(version) as ver,
       max(date) as uploaded
from upload_history
where distribution='unstable' and
      source in (select source
                 from sources
                 where ( maintainer_email='${MAINT}' or
                         uploaders like '%<${MAINT}>%' ) and
                       release='sid')
group by source
order by max(date) asc;
"
