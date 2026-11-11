# AGENTS.md
Shared instructions for all coding agents (Claude Code, Codex) in this repository. Do not create CLAUDE.md or run /init.

## Session start

1. Read this file for operating rules.
2. Read `ARCHITECTURE.md` for units, the module map, and data rules.
3. Consult closed issues, pull requests, and Git history only when historical context is relevant to the task; do not read them all every session.

## Project Context

- The objective is to deliver the developer's intended gameplay.
- `ARCHITECTURE.md` maps modules, responsibilities, files, contracts, and dependencies.
- The documents in `design_docs` describe intended gameplay and are independent of technical implementation.
- The current PRD or approved plan defines the task's scope, technical approach, and acceptance criteria.
- Source code establishes the current implementation, not the intended game design.
- Read supporting documents when relevant to the task, not automatically on every request.

## Authority

- The developer owns all gameplay and creative decisions.
- Do not modify the design_docs unless explicitly authorized.
- Do not proactively audit, critique, reconcile, or flag changes to the design_docs.
- Do not substitute technical preferences for gameplay decisions.
- Request a decision only when an unresolved gameplay choice prevents authorized work from proceeding.

## Planning and Scope

- For a planning-only task, investigate and propose a solution without implementing it.
- Ground proposals in the relevant code, architecture, and known requirements.
- Identify the proposed changes, affected systems, trade-offs, and verification approach.
- Treat the approved PRD or plan as the implementation agreement.
- Approval authorizes the agreed scope; do not request repeated approval for routine decisions within it.
- If new findings require a material change to the approved approach or scope, explain the deviation and obtain approval before proceeding.

## Architecture and Implementation

- Before changing a module's responsibilities or contracts, identify affected dependencies and consumers.
- Verify relevant architectural assumptions against the actual source code.
- Follow the approved scope and preserve established behavior outside it.
- Avoid introducing duplicate ownership, conflicting sources of truth, or unnecessary dependencies.
- Change existing architecture when justified by the approved gameplay requirements; do not preserve unsuitable implementations solely because they already exist.
- Update `ARCHITECTURE.md` when modules, owned files, responsibilities, contracts, or dependencies change.
- Do not introduce unrelated refactoring or speculative infrastructure.

## Code Quality and Verification

- Review changes for correctness, relevant edge cases, architectural violations, and regressions.
- Run focused checks appropriate to the change's complexity and risk.
- Use verified project commands; do not invent commands or claim unperformed tests.
- Prefer tests that establish meaningful behavior over arbitrary coverage targets.
- Treat successful builds and automated tests as technical evidence, not proof of good gameplay.
- Leave final gameplay acceptance to the developer.

## Completion

- Summarize what changed and identify the affected modules.
- Report which checks were performed, their results, and what remains unverified.
- Disclose deviations from the approved plan and any unresolved defects or limitations.
- Distinguish verified facts from assumptions; do not claim success without supporting evidence.
- When explicitly asked to review previous work, compare the requested references against the actual implementation and report evidence-backed findings.
