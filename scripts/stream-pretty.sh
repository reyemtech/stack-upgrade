#!/bin/bash
# Pretty-print Claude Code stream-json output
# Pipes each JSON line through jq to extract readable info

while IFS= read -r line; do
  echo "$line" | jq -r '
    if .type == "assistant" then
      (.message.content[]? |
        if .type == "text" then "[assistant] " + (.text | split("\n")[0] | .[0:300])
        elif .type == "tool_use" then "[tool_use] " + .name + "(" + (.input | keys | join(", ")) + ")"
        else empty end)
    elif .type == "result" then
      "[done] cost=$(.cost_usd // "?") turns=\(.num_turns // "?")"
    else empty end
  ' 2>/dev/null
done
