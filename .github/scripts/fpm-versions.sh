#!/bin/sh
# Prints the PHP versions from versions.json that get the FPM image, as a JSON
# array of {minor, version}. Older versions only get the legacy images.
set -eu

FPM_MIN_VERSION=8.4

jq -c --arg min "$FPM_MIN_VERSION" '
  [ to_entries[]
    | select((.key | split(".") | map(tonumber)) >= ($min | split(".") | map(tonumber)))
    | {minor: .key, version: .value} ]
' versions.json
