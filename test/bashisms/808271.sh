#!/bin/sh

if type which; then
  echo "use which"
fi

if ! type which; then
  echo "well, idk"
fi
