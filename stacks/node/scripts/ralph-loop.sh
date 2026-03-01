#!/bin/bash
# Ralph loop: restart Claude Code if it exits before checklist is done
MAX_RESTARTS=${MAX_RESTARTS:-5}
MAX_TURNS=${MAX_TURNS:-200}
RESTARTS=0
START_TIME=$(date +%s)
EXIT_CODE=0

cd /workspace

# Write initial status
write_status() {
  local phase="$1" status="$2"
  local now=$(date +%s)
  local elapsed=$(( (now - START_TIME) / 60 ))
  jq -n \
    --arg phase "$phase" \
    --arg status "$status" \
    --argjson restarts "$RESTARTS" \
    --argjson elapsed "$elapsed" \
    '{phase: $phase, status: $status, restarts: $restarts, elapsed_minutes: $elapsed}' \
    > /output/status.json
}

write_status "0" "starting"

while [ $RESTARTS -lt $MAX_RESTARTS ]; do
  # Update status with current phase from checklist
  CURRENT_PHASE=$(grep -B1 "status: in_progress\|status: not_started" /workspace/.upgrade/checklist.yaml 2>/dev/null | grep "id:" | head -1 | awk '{print $3}' || echo "unknown")
  write_status "$CURRENT_PHASE" "in_progress"

  echo "$(date -u +%Y-%m-%dT%H:%M) ralph: launching Claude Code (attempt $((RESTARTS + 1))/$((MAX_RESTARTS + 1)))"

  claude --dangerously-skip-permissions \
    --verbose \
    --max-turns "$MAX_TURNS" \
    --output-format stream-json \
    -p "$(cat /skill/kickoff-prompt.txt)" \
    2>&1 | tee /output/claude-run-$((RESTARTS + 1)).jsonl | /skill/scripts/stream-pretty.sh \
    || true

  # Check if checklist has incomplete tasks
  if grep -q "status: not_started\|status: in_progress" /workspace/.upgrade/checklist.yaml 2>/dev/null; then
    RESTARTS=$((RESTARTS + 1))
    echo "$(date -u +%Y-%m-%dT%H:%M) restart: Claude exited with incomplete tasks. Restart $RESTARTS/$MAX_RESTARTS" >> /workspace/.upgrade/run-log.md
    echo "Restarting... ($RESTARTS/$MAX_RESTARTS)"
    write_status "$CURRENT_PHASE" "restarting"
  else
    echo "$(date -u +%Y-%m-%dT%H:%M) complete: All tasks reached terminal state." >> /workspace/.upgrade/run-log.md
    echo "All checklist tasks complete."
    write_status "done" "complete"
    break
  fi
done

if [ $RESTARTS -ge $MAX_RESTARTS ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M) halted: Max restarts ($MAX_RESTARTS) reached with incomplete tasks." >> /workspace/.upgrade/run-log.md
  echo "Max restarts reached. Check run-log.md for details."
  write_status "unknown" "halted"
  EXIT_CODE=1
fi

# Post-run: after-snapshots
echo "Capturing post-upgrade dependency snapshots..."
cd /workspace
jq '{dependencies: (.dependencies // {}), devDependencies: (.devDependencies // {})}' \
  package.json > /output/after-package-deps.json 2>/dev/null || echo "{}" > /output/after-package-deps.json
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml; do
  if [ -f "$lockfile" ]; then
    sha256sum "$lockfile" > /output/after-lockfile-hash.txt
    break
  fi
done

# Post-run: copy artifacts
cp .upgrade/run-log.md .upgrade/checklist.yaml .upgrade/plan.md .upgrade/changelog.md /output/ 2>/dev/null || true
git log --oneline > /output/commits.log 2>/dev/null || true

# Build result.json
TOTAL_PHASES=$(grep -c "id:" /workspace/.upgrade/checklist.yaml 2>/dev/null || echo "0")
COMPLETED=$(grep -c "status: complete" /workspace/.upgrade/checklist.yaml 2>/dev/null || echo "0")
FAILED=$(grep -c "status: failed" /workspace/.upgrade/checklist.yaml 2>/dev/null || echo "0")
ELAPSED=$(( ($(date +%s) - START_TIME) / 60 ))

if [ $EXIT_CODE -eq 0 ]; then
  OUTCOME="success"
else
  OUTCOME="incomplete"
fi

jq -n \
  --arg outcome "$OUTCOME" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson total_phases "$TOTAL_PHASES" \
  --argjson completed "$COMPLETED" \
  --argjson failed "$FAILED" \
  --argjson restarts "$RESTARTS" \
  --argjson elapsed_minutes "$ELAPSED" \
  --arg branch "${BRANCH:-upgrade/node-${STACK_TYPE:-unknown}}" \
  '{outcome: $outcome, exit_code: $exit_code, total_phases: $total_phases, completed: $completed, failed: $failed, restarts: $restarts, elapsed_minutes: $elapsed_minutes, branch: $branch}' \
  > /output/result.json

echo "Result: $(cat /output/result.json)"

# Push
if [ "${GIT_PUSH:-true}" = "true" ]; then
  BRANCH="${BRANCH:-upgrade/node-${STACK_TYPE:-unknown}}"
  echo "Pushing branch $BRANCH..."
  git push origin "$BRANCH" || echo "Push failed — branch may have diverged or deploy key lacks write access."

  # Auto-create PR if GH_TOKEN is provided
  if [ -n "$GH_TOKEN" ]; then
    echo "Creating pull request..."
    export GH_TOKEN

    case "$STACK_TYPE" in
      nextjs) PR_TITLE="Upgrade Next.js to ${TARGET_NEXTJS:-latest}" ;;
      cra) PR_TITLE="Migrate CRA to Vite" ;;
      vite-react) PR_TITLE="Upgrade Vite + React" ;;
      *) PR_TITLE="JS Stack Upgrade" ;;
    esac

    PR_BODY=""
    if [ -f /workspace/.upgrade/changelog.md ]; then
      PR_BODY=$(cat /workspace/.upgrade/changelog.md)
    else
      PR_BODY="Automated JS stack upgrade (${STACK_TYPE:-unknown})."
    fi

    # Detect default branch
    DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
    DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

    gh pr create \
      --title "$PR_TITLE" \
      --body "$PR_BODY" \
      --base "$DEFAULT_BRANCH" \
      --head "$BRANCH" \
      2>&1 && echo "PR created successfully." \
      || echo "PR creation failed (may already exist or gh not authenticated)."
  fi
fi

write_status "done" "$OUTCOME"
echo "Done. Artifacts in /output/"
exit $EXIT_CODE
