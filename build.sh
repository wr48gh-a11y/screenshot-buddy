#!/bin/zsh
# DEPRECATED — kept because older docs and muscle memory still reach for `./build.sh`.
#
# This used to be a second, independent install path: Debug config, ad-hoc signed, no
# duplicate-copy cleanup, and no record of which commit it came from. That made it possible to
# have an app in ~/Applications that no script could identify, which is exactly how a fixed bug
# went on looking broken for half a session on 2026-08-27.
#
# There is now one install path. This forwards to it.
set -e
cd "$(dirname "$0")"

echo "note: build.sh is deprecated. Forwarding to scripts/install-local.sh," >&2
echo "      which signs properly, removes duplicate copies, stamps the commit," >&2
echo "      and verifies the result. Use that directly from now on." >&2
echo "" >&2

exec ./scripts/install-local.sh
