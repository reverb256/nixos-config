#!/usr/bin/env bash
# Visual helpers for elegant justfile output
_header() { printf "\033[1;36m▸\033[0m \033[1m%s\033[0m\n" "$1"; }
_step()   { printf "  \033[2;36m◦\033[0m %s\n" "$1"; }
_done()   { printf "  \033[2;32m✓\033[0m %s\n" "$1"; }
_info()   { printf "  \033[2;90m│\033[0m %s\n" "$1"; }
_time()   { printf "\033[2;90m[%s]\033[0m " "$(date +%H:%M:%S)"; }
