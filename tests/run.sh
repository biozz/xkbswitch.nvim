#!/bin/sh
set -eu
TEST_ROOT=$(mktemp -d /tmp/xkbswitch-test.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT
XDG_DATA_HOME="$TEST_ROOT" nvim --clean --headless -l tests/run.lua
