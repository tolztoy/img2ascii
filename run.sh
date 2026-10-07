#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export LUA_PATH="./?.lua;./?/init.lua;./local/usr/share/lua/5.4/?.lua;./local/usr/share/lua/5.4/?/init.lua;;"
export LUA_CPATH="./local/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;;"
export PATH="$PWD/local/usr/bin:$PATH"
exec ./local/usr/bin/lua5.4 server.lua "$@"
