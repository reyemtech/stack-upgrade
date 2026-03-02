---
phase: 02-web-js-agent-templates
plan: 03
subsystem: templates
tags: [vite, react, templates, agent, claude-md, plan, checklist, codemod]

# Dependency graph
requires: []
provides:
  - Vite+React CLAUDE.md with Startup Protocol, Execution Rules, Constraints, Vite 6 gotchas, Error Recovery
  - Vite+React plan.md with 5 sequential phases covering VITE-01 through VITE-05
  - Vite+React checklist.yaml with matching phases and measurable acceptance criteria
affects: [02-web-js-agent-templates]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CLAUDE.md copied as-is (no envsubst) — no shell variables allowed"
    - "plan.md and checklist.yaml use envsubst variables: TARGET_VITE, TARGET_REACT, UPGRADE_DATE, REPO_URL"
    - "5-phase structure: React bump+codemod, Vite bump+plugin, config changes, TS types codemod, build verify"
    - "types-react-codemod conditionally skipped for JavaScript projects (no tsconfig.json)"
    - "Codemod output committed separately for clean git history"

key-files:
  created: []
  modified:
    - stacks/node/templates/vite-react/CLAUDE.md
    - stacks/node/templates/vite-react/plan.md
    - stacks/node/templates/vite-react/checklist.yaml

key-decisions:
  - "Phase 4 (types-react-codemod) explicitly skips if no tsconfig.json — runtime check documented in both CLAUDE.md and plan.md"
  - "Vite 6 resolve.conditions requires spreading defaultClientConditions/defaultServerConditions — documented as hard constraint"
  - "Codemod commits separated from manual fix commits within Phase 1 — deviation from one-commit-per-phase rule for clean history"

patterns-established:
  - "Vite+React template structure mirrors Laravel but with 5 phases instead of 7"
  - "Link: field per phase pointing to official docs (react.dev, v6.vite.dev, github.com/eps1lon/types-react-codemod)"

requirements-completed: [VITE-01, VITE-02, VITE-03, VITE-04, VITE-05]

# Metrics
duration: 2min
completed: 2026-03-01
---

# Phase 2 Plan 3: Vite+React Agent Templates Summary

**5-phase Vite+React upgrade template set with CLAUDE.md (Vite 6 constraints + TypeScript conditional), plan.md (React 19 codemod + Vite config migration + types-react-codemod), and checklist.yaml (ralph-loop.sh compatible)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-02T02:44:46Z
- **Completed:** 2026-03-02T02:46:49Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- CLAUDE.md with complete agent instructions including Vite 6 specific constraints (resolve.conditions, Sass API, json.stringify), TypeScript conditional for types-react-codemod, and no shell variables
- plan.md with 5 phases covering all VITE-01 through VITE-05 requirements, official doc links per phase, and envsubst variables
- checklist.yaml with 5 matching phases, measurable acceptance criteria, all starting at not_started for ralph-loop.sh compatibility

## Task Commits

Each task was committed atomically:

1. **Task 1: Write Vite+React CLAUDE.md** - `488b9e4` (feat)
2. **Task 2: Write Vite+React plan.md and checklist.yaml** - `04d741e` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `stacks/node/templates/vite-react/CLAUDE.md` - Full agent instructions: Startup Protocol, Execution Rules, Vite 6 constraints, Verification Scripts, Useful Commands, Error Recovery
- `stacks/node/templates/vite-react/plan.md` - 5-phase upgrade plan with envsubst variables and official doc links per phase
- `stacks/node/templates/vite-react/checklist.yaml` - Phase tracking YAML for ralph-loop.sh with 5 phases and measurable acceptance criteria

## Decisions Made
- CLAUDE.md documents `TARGET_REACT` and `TARGET_VITE` as plain text labels in the Useful Commands section (not shell variables) since CLAUDE.md is copied as-is
- Phase 4 (types-react-codemod) uses a hard conditional — the plan explicitly says to skip the entire phase if tsconfig.json does not exist, documented in both CLAUDE.md Constraints and plan.md Phase 4 header
- Codemod commits within Phase 1 are separated from manual fix commits — the plan explicitly allows this exception to the one-commit-per-phase rule for React codemods, matching the CRA template pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three Vite+React template files are complete and production-ready
- Templates plug into the Phase 1 node infrastructure (entrypoint.sh envsubst merge, verify-fast.sh grep checks, ralph-loop.sh checklist parsing)
- Phase 02 (web-js-agent-templates) is now complete — all three stack template sets (Next.js, CRA, Vite+React) should now be done

---
*Phase: 02-web-js-agent-templates*
*Completed: 2026-03-01*
