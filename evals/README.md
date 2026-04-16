# TAB Eval Execution Practices

## Running Evals

### Nondeterminism
Run each eval case **3 times** to account for model nondeterminism. A case passes
only if it passes in at least 2 of 3 runs.

### Baseline Comparison
Compare "with skill" vs "without skill" for each should-trigger eval:
1. Run the prompt **without** the TAB skill loaded → record output
2. Run the prompt **with** the TAB skill loaded → record output
3. Compare: the skill version should demonstrably improve structure, depth, and
   accuracy over the baseline

### Train/Validation Split
Use a **60/40 train/validation split** to avoid overfitting the description:
- **Train set (IDs 1-6, 11-17, 21-24, 27-30):** Use these to iterate on the
  skill description and flow
- **Validation set (IDs 7-10, 18-20, 25-26, 31-34):** Hold out — only run after
  changes are finalized to confirm generalization

### Grading Protocol
For each eval run, grade per assertion:
- **Pass:** The assertion is clearly satisfied in the output
- **Fail:** The assertion is not satisfied or contradicted
- **Partial:** The assertion is partially satisfied (document what's missing)

Record evidence for each grade (quote or reference the relevant output section).

### Timing Data
Record per run:
- Total tokens consumed (input + output)
- Wall-clock duration
- Number of subagent invocations

This data helps track cost/performance trade-offs across skill versions.

## Eval Structure

- **IDs 1-10:** Should-trigger evals with full assertions
- **IDs 11-20:** Should-not-trigger evals (obvious non-matches)
- **IDs 21-26:** Intent detection evals (argument processing)
- **IDs 27-34:** Near-miss evals (shared keywords, different intent)

## Adding New Evals

When adding evals:
1. Include `assertions` array with specific, verifiable claims
2. For should-not-trigger, include `reason` explaining the near-miss
3. Assign to train or validation set before running
4. Run 3x to establish baseline pass rate
