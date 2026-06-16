---
name: feature-maker
description: >
  Explicit orchestration skill for Flutter BLE/GPS app feature work, bug fixes,
  quality checks, and APK builds using verified specialist subagents.
argument-hint: "[phase-0|new-feature|bug-fix|release-apk] [task]" 
---

# Feature Maker Skill
Use this skill only when the user explicitly asks to restructure, implement, fix, verify, or build this Flutter app.
This skill is an orchestrator: decide the mode, invoke only the needed verified subagents, wait for exact completion signals, verify outputs, then continue or stop.
Do not waste turns. Do not run broad work. Do not pretend to use subagents or commands if the environment cannot use them.

## 1. Required Context
Before any agent is invoked, inspect the repo.
Required readable files: `CLAUDE.md`, `plan.md`, `pubspec.yaml`.
Useful when present: `CHANGELOG.md`, `lib/main.dart`, `.claude/agents/*.md`.
Use `plan.md` as architecture and task-order source of truth.
Do not copy `plan.md` into outputs.
Do not invent missing requirements.

## 2. Pre-Flight Check
Run before every mode:
1. Verify current working directory.
2. Verify `CLAUDE.md` exists and is readable.
3. Verify `plan.md` exists and is readable.
4. Verify `pubspec.yaml` exists and is readable.
5. Verify required subagent files before invoking them.
6. If commands/builds are required, verify shell access with `pwd`.
7. If Flutter/Dart checks are required, verify `flutter --version` and `dart --version`.
8. If a fix loop may run, verify or create `.claude/run-state/feature-maker-loop.md`.
If required files are missing, stop and report the missing path.
If CLI is unavailable, mark commands `NOT RUN — CLI unavailable`.
If subagents are unavailable, stop before pretending to orchestrate them.

## 3. Required Subagents
Expected files:
- `.claude/agents/planner.md`
- `.claude/agents/coder.md`
- `.claude/agents/quality-checker.md`
- `.claude/agents/researcher.md`
- `.claude/agents/apk-builder.md`
Before invoking an agent, verify its file exists and is readable.
If an agent is missing, report `BLOCKED — missing subagent: <path>` and stop that pipeline.
Do not silently simulate a missing agent.
Invoke only the agent required by the current step.
Do not invoke the next agent until the current completion signal appears and verification passes.

## 4. Mode Selection
Choose exactly one mode.
Use `phase-0` when the user asks to change project structure or split a monolithic app without adding major features.
Use `new-feature` when the user asks for one planned module or one small feature from `plan.md`.
Use `bug-fix` when the user reports APK/manual phone failure, crash, broken behavior, build failure, or logs/errors.
Use `release-apk` when the user wants a build only and no feature change.
If a task is broad, split it and run only the first safe unit.

## 5. Completion Signals
Each subagent must end with exactly one signal:
- Planner: `PLANNER_DONE`
- Researcher: `RESEARCH_DONE`
- Coder: `CODER_DONE`
- Quality-checker: `QUALITY_PASS` or `QUALITY_FAIL`
- APK-builder: `APK_BUILD_DONE` or `APK_BUILD_FAILED`
If the expected signal is absent, ask the same agent once for a corrected final status.
If the signal is still absent, stop.

## 6. Phase 0 Structure Refactor Pipeline
Use when structure must be changed before feature work.
Flow: `planner → coder → quality-checker`.
Do not invoke researcher.
Do not invoke apk-builder unless the user explicitly asks after quality passes.

### Step 1 — Invoke Planner
Invoke `planner` with:
"Read `CLAUDE.md`, `plan.md`, `pubspec.yaml`, and current `lib/` structure. Create a structure-only refactor plan. Goal: split the existing app into the architecture from `plan.md` while preserving current behavior. Do not write code. Output files to inspect, files to move/create, acceptance criteria, risks, and verification commands. End with `PLANNER_DONE`."
Wait for `PLANNER_DONE`.
Verify the planner included acceptance criteria.

### Step 2 — Invoke Coder
Invoke `coder` with:
"Read `CLAUDE.md`, `plan.md`, and the planner output. Perform only the Phase 0 structure refactor. Keep `lib/main.dart` minimal. Create/use `app.dart`, `models/`, `services/`, `screens/`, and `widgets/` as appropriate. Preserve existing BLE, GPS, alarm, map, CSV/cache, and pending-file behavior. Do not add new planned features. Run formatting if CLI is available. End with `CODER_DONE`."
Wait for `CODER_DONE`.
Verify expected folders/files exist before quality review.

### Step 3 — Invoke Quality-checker
Invoke `quality-checker` with:
"Review the Phase 0 refactor. Verify scope, architecture, imports, behavior preservation, and build readiness. Run or request: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`. Classify findings as Blocker, High, Medium, or Low. End with `QUALITY_PASS` only if no Blocker/High issues remain; otherwise end with `QUALITY_FAIL`."
Wait for `QUALITY_PASS` or `QUALITY_FAIL`.
If `QUALITY_FAIL`, use the fix loop policy.

## 7. New Feature Pipeline
Use for exactly one coherent feature/task.
Flow: `planner → coder → quality-checker → apk-builder`.
Invoke apk-builder only after `QUALITY_PASS`.

### Step 1 — Invoke Planner
Invoke `planner` with:
"Read `CLAUDE.md`, `plan.md`, and files relevant to this task: <TASK>. Produce a small implementation plan only for this feature. Include files to inspect/change, acceptance criteria, risks, and verification commands. Do not write code. End with `PLANNER_DONE`."
Wait for `PLANNER_DONE`.
Verify the plan is scoped to one feature.

### Step 2 — Invoke Coder
Invoke `coder` with:
"Read `CLAUDE.md`, `plan.md`, the planner output, and relevant files. Implement only this feature: <TASK>. Keep changes scoped. Preserve existing working BLE, GPS, alarm, map, CSV/cache, and file behavior unless the task explicitly changes it. Run `dart format .` if CLI is available. End with `CODER_DONE`."
Wait for `CODER_DONE`.
Verify changed files are relevant to the task.

### Step 3 — Invoke Quality-checker
Invoke `quality-checker` with:
"Review the implemented feature against `plan.md`, `CLAUDE.md`, and planner acceptance criteria. Run or request: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`. Classify findings as Blocker, High, Medium, or Low. End with `QUALITY_PASS` only if no Blocker/High issues remain; otherwise end with `QUALITY_FAIL`."
Wait for `QUALITY_PASS` or `QUALITY_FAIL`.
If `QUALITY_FAIL`, use the fix loop policy.
If `QUALITY_PASS`, continue.

### Step 4 — Invoke APK-builder
Invoke `apk-builder` with:
"Quality passed for this feature. Build APK only; do not edit feature code. Run `flutter build apk --debug` unless the user requested release. If release was requested, run `flutter build apk --release`. Verify the APK path. Report build command, APK path, version if available, warnings, and manual phone test notes. End with `APK_BUILD_DONE` if successful; otherwise end with `APK_BUILD_FAILED`."
Wait for APK signal.
Do not claim success unless APK path is verified.

## 8. Bug Fix Pipeline
Use for crashes, manual APK bugs, build failures, or broken behavior.
Flow: `researcher → coder → quality-checker → apk-builder`.
Do not invoke planner unless the bug is actually a redesign.
Invoke apk-builder only after `QUALITY_PASS`.

### Step 1 — Invoke Researcher
Invoke `researcher` with:
"Read `CLAUDE.md`, `plan.md`, the bug report, relevant logs/errors, and affected files. Investigate root cause. Do not edit code. Output evidence, likely cause, affected files, safest minimal fix, regression risks, and verification commands. End with `RESEARCH_DONE`."
Wait for `RESEARCH_DONE`.
Verify the researcher gave a concrete recommended fix.

### Step 2 — Invoke Coder
Invoke `coder` with:
"Read the researcher output, `CLAUDE.md`, `plan.md`, and affected files. Apply only the safest minimal fix for the reported bug. Do not add unrelated features. Preserve current working behavior. Run `dart format .` if CLI is available. End with `CODER_DONE`."
Wait for `CODER_DONE`.
Verify changed files match the researched fix.

### Step 3 — Invoke Quality-checker
Invoke `quality-checker` with:
"Review the bug fix against the bug report and researcher output. Check for regressions in nearby BLE, GPS, alarm, map, CSV/cache, and file behavior. Run or request: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`. Classify findings as Blocker, High, Medium, or Low. End with `QUALITY_PASS` only if no Blocker/High issues remain; otherwise end with `QUALITY_FAIL`."
Wait for `QUALITY_PASS` or `QUALITY_FAIL`.
If `QUALITY_FAIL`, use the fix loop policy.
If `QUALITY_PASS`, continue.

### Step 4 — Invoke APK-builder
Invoke `apk-builder` with:
"Quality passed for the bug fix. Build APK only; do not edit feature code. Run `flutter build apk --debug` unless the user requested release. Verify APK path. Report build command, APK path, version if available, warnings, and exact manual re-test steps for the bug. End with `APK_BUILD_DONE` if successful; otherwise end with `APK_BUILD_FAILED`."
Wait for APK signal.

## 9. Release APK Only Pipeline
Use when the user wants a build without code changes.
Flow: `quality-checker → apk-builder`.

### Step 1 — Invoke Quality-checker
Invoke `quality-checker` with:
"Perform final pre-build verification. Do not edit code. Run or request: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`. Classify findings. End with `QUALITY_PASS` only if no Blocker/High issues remain; otherwise end with `QUALITY_FAIL`."
Wait for quality signal.
If `QUALITY_FAIL`, stop unless the user explicitly asks to fix.

### Step 2 — Invoke APK-builder
Invoke `apk-builder` with:
"Quality passed. Build release APK only. Run `flutter build apk --release`. Verify the APK path and report it. Do not edit code. End with `APK_BUILD_DONE` if successful; otherwise end with `APK_BUILD_FAILED`."
Wait for APK signal.

## 10. Fix Loop Policy
Maximum 3 coder-fix loops per task.
The loop limit must be enforced externally when possible.
Preferred enforcement: orchestrator script.
Fallback enforcement: `.claude/run-state/feature-maker-loop.md`.
A loop is `coder → quality-checker`.
Before each loop: read loop count, stop if next loop is 4, increment count before coder, record the Blocker/High issue.
If quality fails, invoke coder again only for Blocker/High issues.
Do not fix Medium/Low issues unless user asks or they block functionality.
Reinvoke quality-checker after coder.
Stop after 3 failed loops.
If loop state cannot be verified, allow one repair attempt only, then stop if Blocker/High issues remain.
Never invoke apk-builder while Blocker/High issues remain.

## 11. Quality Gates
Quality-checker must report real command results when CLI is available.
Required checks: `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.
Release build: `flutter build apk --release`.
If a command is not run, say why.
Do not mark `QUALITY_PASS` if required checks failed without accepted reason.
Do not mark APK built unless build succeeds or APK path exists.

## 12. Documentation and Memory
Update `CHANGELOG.md` only after meaningful completed changes.
Use headings: `Added`, `Changed`, `Fixed`, `Known Issues`.
Do not dump logs into changelog.
Do not record temporary failed attempts unless they create a known issue.
Update agent memory only with durable project lessons.
Never store secrets, credentials, signing passwords, private keys, or API keys.

## 13. Final Response Format
End every run with:
```text
Mode used:
Task handled:
Agents invoked:
Files changed:
Commands run / NOT RUN:
Quality result:
APK built: yes/no
Changelog updated: yes/no
Memory updated: yes/no
Remaining risks:
Next recommended step:
```
Keep the final answer factual and based only on verified work.

## 14. Invocation Examples
Phase 0: `/feature-maker phase-0 Restructure the project according to plan.md without adding new features.`
New feature: `/feature-maker new-feature Implement Week 1 Task 2: DatabaseService and Survey/Measurement/Reading models only.`
Bug fix: `/feature-maker bug-fix APK crashes when Mark Leak is saved after attaching a photo. Steps: ...`
Release APK: `/feature-maker release-apk Run final checks and build release APK only if no Blocker/High issues remain.`
