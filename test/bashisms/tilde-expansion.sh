#!/bin/sh

echo tilde alone: ~/
echo tilde with name: ~root/

cd ; cd - >/dev/null

echo BASHISM: tilde plus: ~+
echo BASHISM: tilde minus: ~-

pushd ~ >/dev/null 2>&1	    # BASHISM
for i in $(seq 1 9); do
    pushd / >/dev/null 2>&1 # BASHISM
done

echo BASHISM: tilde plus n: ~+1
echo BASHISM: tilde implicit plus n: ~1
echo BASHISM: tilde minus n: ~-1

echo BASHISM: tilde plus 10: ~+10
echo BASHISM: tilde implicit plus 10: ~10
echo BASHISM: tilde minus 10: ~-10

echo BASHISM=~-/bin
echo BASHISM=/:~+/bin/
BASHISM=~-/bin ; echo $BASHISM
BASHISM=/:~+/bin/ ; echo $BASHISM

echo nothing wrong here: ~+foo/
echo nothing wrong here: ~-moo/
echo nothing wrong here: ~+1foo/
echo nothing wrong here: ~1foo/
echo nothing wrong here: ~-1moo/

# Again, but without the slash
echo nothing wrong here: ~+foo
echo nothing wrong here: ~-moo
echo nothing wrong here: ~+1foo
echo nothing wrong here: ~1foo
echo nothing wrong here: ~-1moo

