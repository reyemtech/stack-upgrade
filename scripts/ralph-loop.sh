#!/bin/bash
# Ralph loop: restart Claude Code if it exits before checklist is done
MAX_RESTARTS=${MAX_RESTARTS:-5}
RESTARTS=0

cd /workspace

while [ $RESTARTS -lt $MAX_RESTARTS ]; do
  echo "$(date -u +%Y-%m-%dT%H:%M) ralph: launching Claude Code (attempt $((RESTARTS + 1))/$((MAX_RESTARTS + 1)))"

  claude --dangerously-skip-permissions \
    --print \
    -p "$(cat /skill/kickoff-prompt.txt)" \
    || true

  # Check if checklist has incomplete tasks
  if grep -q "status: not_started\|status: in_progress" /workspace/checklist.yaml 2>/dev/null; then
    RESTARTS=$((RESTARTS + 1))
    echo "$(date -u +%Y-%m-%dT%H:%M) restart: Claude exited with incomplete tasks. Restart $RESTARTS/$MAX_RESTARTS" >> /workspace/run-log.md
    echo "Restarting... ($RESTARTS/$MAX_RESTARTS)"
  else
    echo "$(date -u +%Y-%m-%dT%H:%M) complete: All tasks reached terminal state." >> /workspace/run-log.md
    echo "All checklist tasks complete."
    break
  fi
done

if [ $RESTARTS -ge $MAX_RESTARTS ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M) halted: Max restarts ($MAX_RESTARTS) reached with incomplete tasks." >> /workspace/run-log.md
  echo "Max restarts reached. Check run-log.md for details."
fi

# Post-run: copy artifacts + push
cd /workspace
cp run-log.md checklist.yaml plan.md /output/ 2>/dev/null || true
git log --oneline > /output/commits.log 2>/dev/null || true

if [ "${GIT_PUSH:-true}" = "true" ]; then
  echo "Pushing branch upgrade/laravel-${TARGET_LARAVEL}..."
  git push origin "upgrade/laravel-${TARGET_LARAVEL}" || echo "Push failed — check deploy key permissions."
fi

echo "Done. Artifacts in /output/"
