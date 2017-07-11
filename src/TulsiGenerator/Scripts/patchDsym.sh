#!/bin/bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <dwarfpatcher> <dsym> <real-workspace> <bazel-workspace>"
  exit 1
fi

DWARFPATCHER="$1"
DSYM="$2"
REAL_WORKSPACE="$3"
# for some reason, we need the tulsi project to begin without the leading /private, not sure why
# The bash magic here just strips that /private prefix
BAZEL_WORKSPACE="/${4#/*/}"

PREFIX_MAP=$(mktemp)
# for ($TO_REPLACE, $RELATIVE_PATH) in dwarf symbols
for p in $(xcrun dwarfdump "$DSYM" -r 0 | grep AT_comp_dir -B2 | grep -v '\-\-' | awk 'NR%3{printf "%s ",$0;next;}1' | grep 'bazel' | perl -pe 's/.*?AT_name.."+(.*?)".*?"(.*?)"\s.*/\2,\1/g' | sort | uniq); do
    IFS=","; set -- $p
    TO_REPLACE="$1"
    RELATIVE_PATH="$2"

    # Dwarfpatch expects a file with sed-style ,needle,new-needle, replacements per line
    # Here we use the bazel sandbox path and replace it with the path to our iOS workspace
    #
    # Dwarfpatch uses this file to fix our dSYM
    if [[ "$RELATIVE_PATH" == external* ]]; then
      # HACK: Temporarily use REAL_WORKSPACE here to support non-sandboxed builds.
      echo ",$TO_REPLACE,$REAL_WORKSPACE," >> "$PREFIX_MAP"
    else
      echo ",$TO_REPLACE,$REAL_WORKSPACE," >> "$PREFIX_MAP"
    fi
done
"$DWARFPATCHER" -d -m "$PREFIX_MAP" "$DSYM"
rm "$PREFIX_MAP"
