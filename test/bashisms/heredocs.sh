#!/bin/sh

cat <<- FOO
    foo
	bar
    moo
FOO

echo -e moo # BASHISM

foo() {
	cat <<- FOO
	foo
	bar
	moo
	FOO
	echo -e BASHISM
}

bar() {
	cat <<- FOO
	foo
	bar
	moo
    FOO
    echo -e nothing wrong here
FOO
	echo -e BASHISM
}


moo() {
	cat << FOO
	foo
	bar
	moo
    FOO
    echo -e nothing wrong here
	FOO
	echo -e still nothing wrong here
FOO
	echo -e BASHISM
}

baz() {
    cat << EOF1
EOF1 
    echo -e still inside the here doc
EOF1 ; echo -e still inside...
EOF1
    echo -e BASHISM
}
