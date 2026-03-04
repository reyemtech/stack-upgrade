#!/bin/bash
# Pretty-print agent stream output (Claude Code stream-json or Codex --json)

while IFS= read -r line; do
  # Detect format from JSON structure and pretty-print accordingly
  echo "$line" | jq -r '
    # Claude Code stream-json format
    if .type == "assistant" then
      (.message.content[]? |
        if .type == "text" then ">> " + (.text | split("\n")[0] | .[0:300])
        elif .type == "tool_use" then "=> " + .name + " " + (.input | to_entries | map(.key + "=" + (.value | tostring | .[0:80])) | join(" "))
        elif .type == "thinking" then ".. " + (.thinking | split("\n")[0] | .[0:200])
        else empty end)
    elif .type == "tool_result" then
      "   ok " + (.content // "" | tostring | split("\n")[0] | .[0:200])
    elif .type == "result" then
      "== Done. cost=$" + (.cost_usd // 0 | tostring) + " turns=" + (.num_turns // 0 | tostring)
    # Codex --json format
    elif .event == "message" then
      ">> " + (.content // "" | tostring | split("\n")[0] | .[0:300])
    elif .event == "tool_call" then
      "=> " + (.name // "tool") + " " + (.arguments // "" | tostring | .[0:200])
    elif .event == "tool_result" then
      "   ok " + (.output // "" | tostring | split("\n")[0] | .[0:200])
    elif .event == "completed" then
      "== Done."
    elif .event == "error" then
      "!! " + (.message // "unknown error" | tostring | .[0:300])
    else empty end
  ' 2>/dev/null
done
