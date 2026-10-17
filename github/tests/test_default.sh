#!/bin/sh

basedir=$(dirname "$0")

test "$("$basedir"/../run.sh)" = "Hello world!" && echo "Test passed!"
