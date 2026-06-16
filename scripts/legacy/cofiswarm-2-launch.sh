#!/usr/bin/env bash

./cofiswarm-check-conda.sh || {
    echo "Aborting."
    exit 1
}

# Point the proxy at the freshly-built llama-server. The default
# /Users/Shared/llama/llama-server (Apr 2026) has a dangling @rpath to
# llama.cpp/build/bin/libmtmd.0.dylib and crashes on load. The build under
# llama.cpp-master ships its dylibs alongside the binary, so it loads cleanly.
export MATRIX_LLAMA_SERVER="${MATRIX_LLAMA_SERVER:-/Users/Shared/llama/llama.cpp-master/build/bin/llama-server}"

./brewctl up
