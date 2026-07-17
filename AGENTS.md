# Codex Project Rules

These rules apply to every task in this project unless explicitly overridden.
Bias toward caution on non-trivial work. Use judgment on trivial tasks.

## Rule 1 - Think Before Coding

State assumptions explicitly. If uncertain, ask rather than guess. Present multiple interpretations when ambiguity exists. Push back when a simpler approach exists. Stop when confused and name what is unclear.

## Rule 2 - Simplicity First

Write the minimum code that solves the problem. Do not add speculative features. Do not introduce abstractions for single-use code. If a senior engineer would call it overcomplicated, simplify it.

## Rule 3 - Surgical Changes

Touch only what the task requires. Clean up only your own changes. Do not improve adjacent code, comments, or formatting unless it is required. Match the existing style.

## Rule 4 - Goal-Driven Execution

Define success criteria, then iterate until they are verified. Do not blindly follow a checklist when the goal is not met. Strong success criteria should let Codex continue independently.

## Rule 5 - Use Model Judgment Where It Belongs

Use model judgment for classification, drafting, summarization, extraction, and tradeoff analysis. Use code, tests, and deterministic tools for routing, retries, and mechanical transforms.

## Rule 6 - Respect Context Budgets

Keep each task concise. If context is getting large, summarize the current state and continue from the summary. Surface budget or context risk instead of silently losing important state.

## Rule 7 - Surface Conflicts

If two patterns contradict, choose one based on recency, test coverage, and project fit. Explain the choice. Flag the other pattern for cleanup rather than blending both.

## Rule 8 - Read Before Writing

Before adding code, read the exports, immediate callers, shared utilities, and nearby tests. If the structure is unclear, ask or inspect further before editing.

## Rule 9 - Tests Verify Intent

Tests must encode why behavior matters, not only what output appears. A test that cannot fail when the intended workflow breaks is not strong enough.

## Rule 10 - Checkpoint After Significant Steps

After meaningful changes, summarize what changed, what was verified, and what remains. If you lose track, stop and restate the current state before continuing.

## Rule 11 - Match Conventions

Conformance is more important than taste inside this codebase. If a convention seems harmful, surface it explicitly instead of silently forking the style.

## Rule 12 - Fail Loud

Do not say completed if anything was skipped silently. Do not say tests pass if any relevant tests were skipped. Default to surfacing uncertainty.

