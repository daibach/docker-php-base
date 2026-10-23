#!/bin/sh
# Decides which PHP patch version tags (X.Y.Z) to delete from Docker Hub.
# Reads the repository's tags, as printed by hub-tags.sh, on stdin and prints
# a JSON array of {name, last_pulled, action, reason}, newest first. Within
# each minor version the newest KEEP tags are kept, as is the current version
# in versions.json and any tag pulled in the last PULL_DAYS days. Other tags
# (X.Y, legacy variants) are never pruned.
set -eu

KEEP=${KEEP:-3}
PULL_DAYS=${PULL_DAYS:-30}
NOW=${NOW:-$(date -u +%s)}

jq -c --argjson keep "$KEEP" --argjson days "$PULL_DAYS" --argjson now "$NOW" \
  --slurpfile versions versions.json '
  def version: split(".") | map(tonumber);
  def timestamp: if . == null then null else sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 end;
  ($versions[0] | [.[]]) as $current
  | [ .[] | select(.name | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) ]
  | group_by(.name | version | .[:2])
  | map(sort_by(.name | version) | reverse | to_entries[])
  | map(
      .key as $rank | .value as $tag
      | ($tag.tag_last_pulled | timestamp) as $pulled
      | {name: $tag.name, last_pulled: $tag.tag_last_pulled}
      + if any($current[]; . == $tag.name) then
          {action: "keep", reason: "current version"}
        elif $rank < $keep then
          {action: "keep", reason: "one of the newest \($keep)"}
        elif $pulled != null and $now - $pulled < $days * 86400 then
          {action: "keep", reason: "pulled in the last \($days) days"}
        else
          {action: "delete", reason: "not pulled in the last \($days) days"}
        end)
  | sort_by(.name | version) | reverse
'
