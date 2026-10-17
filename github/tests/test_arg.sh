#!/bin/sh

basedir=$(dirname "$0")

test "$(WHO="Jean" "$basedir"/../run.sh)" = "Hello Jean!" && echo "Test passed!"
