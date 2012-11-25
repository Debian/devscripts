#!/bin/sh
metric=0
echo $((metric=metric+1))

m=0
n=2
echo $((n-m++)) # BASHISM
echo $((++m))   # BASHISM
echo $(( m-- )) # BASHISM
echo $((--m))   # BASHISM

foo_bar=0
echo $((foo_bar++)) # BASHISM
echo $((foo_bar=foo_bar*2))
echo $((foo_bar*3/6))

echo $((2*n++)) # BASHISM

echo $(($n*n++)) # BASHISM

echo $((3**2)) # BASHISM
