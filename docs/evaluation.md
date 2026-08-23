# Skill evaluation

The repository has two evaluation layers:

1. `tests/validate-skill-evals.ps1` validates that representative behavior
   cases and observable expectations remain present. It is deterministic and
   runs in CI.
2. `tests/run-skill-evals.ps1 -ApproveCost` runs the same cases through Codex
   in an ephemeral read-only sandbox. It is opt-in because it consumes model
   quota and depends on the caller's authenticated Codex environment.

The suite covers non-triggering ordinary explanations, design-only status,
verification-boundary status classification, redaction, missing update-only targets, and
idempotent duplicate evidence. Add a case when a demonstrated behavioral
failure cannot be protected by deterministic script tests alone.

Live evaluation never configures Obsidian or approves writes. Review failures
as decision regressions; do not weaken an expectation solely to make a model
run pass.
