/* Wrapper for debpkg so that we don't have to use suidperl any longer
   (it's deprecated as of Perl 5.8.0) */

#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

#define REAL_PATH "/usr/share/devscripts/debpkg"

int main(int ac, char **av)
{
  execv(REAL_PATH, av);

  fprintf(stderr, "Error executing debpkg: %s\n", strerror(errno));
  return 1;
}
