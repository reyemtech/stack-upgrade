#!/bin/bash
# Pretty-print Claude Code stream-json output

while IFS= read -r line; do
  echo "$line" | jq -r '
    if .type == "assistant" then
      (.message.content[]? |
        if .type == "text" then "💬 " + (.text | split("\n")[0] | .[0:300])
        elif .type == "tool_use" then "🔧 " + .name + " " + (.input | to_entries | map(.key + "=" + (.value | tostring | .[0:80])) | join(" "))
        elif .type == "thinking" then "🧠 " + (.thinking | split("\n")[0] | .[0:200])
        else empty end)
    elif .type == "tool_result" then
      "   ✓ " + (.content // "" | tostring | split("\n")[0] | .[0:200])
    elif .type == "result" then
      "✅ Done. cost=$" + (.cost_usd // 0 | tostring) + " turns=" + (.num_turns // 0 | tostring)
    else empty end
  ' 2>/dev/null
done
