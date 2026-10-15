# programs

Context `none`, model `ollama/gpt-oss:120b`, judge `none`, 3 trials per task, started 2026-10-04T21:56:58.751Z.

Pass rate **58%** (95% CI 9%–100%) over 4 tasks, mean score 71%.

| Task | Tags | Passed | pass@3 | pass^3 | Score | Model calls | Failed runs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| count_words | values | 0/3 | 0% | 0% | 50% | 4.3 | 0.3 |
| fibonacci | arithmetic | 3/3 | 100% | 100% | 100% | 3.7 | 0.7 |
| list_second | values | 1/3 | 100% | 0% | 33% | 5.0 | 1.3 |
| record_update | values | 3/3 | 100% | 100% | 100% | 3.3 | 0.0 |

## By tag

| Tag | Tasks | Pass rate | 95% CI |
| --- | --- | --- | --- |
| values | 3 | 44% | 0%–100% |
| arithmetic | 1 | 100% | insufficient tasks |

## Failing checks

- **count_words** computes 4 (3×): no program computed 4, the last value computed was {}
- **list_second** computes "b" (2×): no program computed "b", the last value computed was {}
