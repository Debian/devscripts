#!/bin/sh

# This is a TO DO, but irrelevant to this test case:
foo=(foo bar moo BASH ISM)

n=1

echo BASHISM ${foo[1]%r}
echo BASHISM ${foo[$n]%r}
echo BASHISM ${foo[*]%o}
echo BASHISM ${foo[@]%o}

echo BASHISM ${foo[1]%%r}
echo BASHISM ${foo[$n]%%r}
echo BASHISM ${foo[*]%%o}
echo BASHISM ${foo[@]%%o}

echo BASHISM ${foo[1]#*a}
echo BASHISM ${foo[$n]#*a}
echo BASHISM ${foo[*]#*o}
echo BASHISM ${foo[@]#*o}

echo BASHISM ${foo[1]##*a}
echo BASHISM ${foo[$n]##*a}
echo BASHISM ${foo[*]##*o}
echo BASHISM ${foo[@]##*o}

echo BASHISM ${#foo[1]}
echo BASHISM ${#foo[$n]}
echo BASHISM ${#foo[*]}
echo BASHISM ${#foo[@]}

# Technically, there are two bashisms here, but I'm happy if it at
# least matches one. The regexes become more complex without real gain
# otherwise. (hence the "BASH ISMS", with the extra space)

echo BASHISM BASH ISMS ${foo[1]^*a}
echo BASHISM BASH ISMS ${foo[$n]^*a}
echo BASHISM BASH ISMS ${foo[*]^*o}
echo BASHISM BASH ISMS ${foo[@]^*o}

echo BASHISM BASH ISMS ${foo[1]^^*a}
echo BASHISM BASH ISMS ${foo[$n]^^*a}
echo BASHISM BASH ISMS ${foo[*]^^*o}
echo BASHISM BASH ISMS ${foo[@]^^*o}

echo BASHISM BASH ISMS ${foo[1],*a}
echo BASHISM BASH ISMS ${foo[$n],*a}
echo BASHISM BASH ISMS ${foo[*],*a}
echo BASHISM BASH ISMS ${foo[@],*a}

echo BASHISM BASH ISMS ${foo[1],,*a}
echo BASHISM BASH ISMS ${foo[$n],,*a}
echo BASHISM BASH ISMS ${foo[*],,*a}
echo BASHISM BASH ISMS ${foo[@],,*a}

echo BASHISM BASH ISMS ${foo[1]/a/R}
echo BASHISM BASH ISMS ${foo[$n]/a/R}
echo BASHISM BASH ISMS ${foo[*]/a/R}
echo BASHISM BASH ISMS ${foo[@]/a/R}
