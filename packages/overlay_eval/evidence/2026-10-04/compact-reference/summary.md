# programs

Context `none`, model `ollama/gpt-oss:120b`, judge `none`, 3 trials per task, started 2026-10-04T21:59:23.419Z.

Pass rate **42%** (95% CI 1%–83%) over 4 tasks, mean score 50%.

| Task | Tags | Passed | pass@3 | pass^3 | Score | Model calls | Failed runs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| count_words | values | 1/3 | 100% | 0% | 67% | 1.7 | 0.3 |
| fibonacci | arithmetic | 1/3 | 100% | 0% | 33% | 9.0 | 5.7 |
| list_second | values | 0/3 | 0% | 0% | 0% | 7.3 | 6.3 |
| record_update | values | 3/3 | 100% | 100% | 100% | 3.0 | 0.7 |

## By tag

| Tag | Tasks | Pass rate | 95% CI |
| --- | --- | --- | --- |
| values | 3 | 44% | 0%–100% |
| arithmetic | 1 | 33% | insufficient tasks |

## Failing checks

- **list_second** computes "b" (3×): no program computed "b", no program computed a value
- **count_words** computes 4 (2×): no program computed 4, no program computed a value
- **fibonacci** computes 17710 (2×): no program computed 17710, no program computed a value
