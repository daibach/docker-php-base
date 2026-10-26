#!/bin/sh
# Prints the PHP versions from versions.json as a JSON array of
# {minor, version}.
set -eu

jq -c '[ to_entries[] | {minor: .key, version: .value} ]' versions.json
