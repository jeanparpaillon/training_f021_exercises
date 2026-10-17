#!/bin/sh

rm -rf dist
mkdir dist


cat <<EOF > dist/index.html
<html>
    <head>
        <title>SGA Doc</title>
    </head>
    <body>
        <h1>SGA Doc</h1>


        $(cat README.md)
</html
EOF
