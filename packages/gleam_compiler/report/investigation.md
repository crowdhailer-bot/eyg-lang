# Continuing the compiler investigation

This companion records the new experiments. The [report](index.html) and
[40 minute presentation](deck.html) include the original evidence passing,
generator and browser API investigation. Historical timings in `results.js`
belong to the earlier compiler; new measurements are stored separately.

## Correctness before speed

The JS builtins silently rounded overflowing integer arithmetic and parsing.
They now reject unrepresentable results, matching the interpreter's boundary
at ±(2^53 − 1). Tests exercise the boundary and rejection across both backends
and every evidence configuration. The compiler reports an error; it does not
yet serialize interpreter state for migration to an arbitrary precision host.

All subsequent timings include these checks. Removing suspension checks from
pure calls does not justify removing arithmetic checks.
