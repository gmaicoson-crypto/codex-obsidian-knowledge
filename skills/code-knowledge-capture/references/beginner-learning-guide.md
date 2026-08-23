# Beginner learning guide

Use this guide when drafting the default `audience: beginner-programmer`
capture. Its purpose is to make repository-specific code understandable and
learnable without weakening technical accuracy.

## Explanation order

Teach in this order unless the evidence clearly calls for another sequence:

1. **Outcome** — what the project or feature lets the user do.
2. **Prerequisites** — the minimum ideas needed for this note; link or explain
   them inline instead of assuming broad computer-science knowledge.
3. **Mental model** — a small, literal model of the components and flow. Avoid
   metaphors that hide important behavior.
4. **Vocabulary** — define each important term at first use with a plain
   explanation and a concrete location in the repository.
5. **Guided code path** — follow one real input from entry point through core
   logic to output, then cover one relevant failure or edge path.
6. **Why this design** — compare the chosen approach with the most relevant
   alternative, including the cost accepted.
7. **Verification and debugging** — distinguish static inspection, tests,
   builds, and actual runtime evidence; show what to observe when behavior is
   wrong.
8. **Retrieval practice** — finish with explain-back questions and one or more
   safe exercises tied to the actual code.

## Two-layer explanations

For an important concept, start with a short `通俗理解` paragraph, then add
`在本项目中` with exact paths, symbols, configuration keys, or test names.
Use a tiny concrete example when it reduces ambiguity. Do not replace the
technical layer with analogy.

When code syntax is likely unfamiliar and materially affects behavior, explain
only the relevant construct beside the excerpt. Examples include async/await,
dependency injection, callbacks, generic types, decorators, shell pipelines,
or framework lifecycle hooks. Do not create a generic language tutorial.

## Vocabulary quality

Each key term entry should contain:

- the original term and an optional Chinese name;
- a one-sentence plain-language definition;
- its job in this project or feature;
- a source location or `无证据`;
- one commonly confused term or beginner misconception when relevant.

Prefer 5–12 high-value terms over an exhaustive glossary. Reuse a project-level
definition instead of duplicating it in every feature note; feature notes may
add a narrower meaning or link back.

## Code walkthrough quality

Select 1–3 short source excerpts that together reveal the behavior. For each
excerpt explain:

- what arrives as input and where it came from;
- what the highlighted statements do;
- what value, state, or side effect leaves the excerpt;
- what calls the code next or consumes the result;
- which syntax or API is essential to understanding it;
- what would be observed if this step failed.

Use actual repository source. If line numbers are unstable, prefer a symbol or
configuration key. Keep omitted text marked with `...`; never invent missing
source to make an example look complete.

## Architecture for beginners

Describe architecture at three zoom levels:

1. **System boundary** — users/external systems, this project, and persistent
   storage or services.
2. **Component map** — each component's single main responsibility and its
   inputs/outputs.
3. **One numbered flow** — trigger, entry point, transformation/state change,
   output, and observable result.

Call out ownership boundaries, trust boundaries, and invariants only when
supported by evidence. Clearly label an inferred boundary as `[推断]`.

## Self-checks and exercises

Self-checks should test understanding, not trivia. Include:

- 3–5 explain-back questions whose answers are present in the notes;
- 1–3 small exercises such as tracing a different input, predicting an error
  result, locating a symbol, adding a focused test, or changing a safe local
  constant;
- expected observations or answer points;
- safety or environment constraints and a reset method when needed.

Do not instruct a beginner to mutate production data, expose credentials,
deploy, delete files, or run destructive commands merely for practice. If no
safe evidence-based exercise exists, say so and provide a read-only tracing
exercise.

## Anti-patterns

Avoid:

- unexplained acronyms or framework names;
- a glossary disconnected from real files and symbols;
- line-by-line paraphrase without the end-to-end flow;
- claiming a cause only because a test passed;
- exercises without expected observations;
- presenting plans or inferred architecture as implemented fact;
- overwhelming the reader with every file, option, or edge case at once.
