# programs

Context `none`, model `ollama/gpt-oss:120b`, judge `none`, 3 trials per task, started 2026-10-15T00:00:07.613Z.

Pass rate **83%** (95% CI 64%–100%) over 4 tasks, mean score 83%.

| Task | Tags | Passed | pass@3 | pass^3 | Score | Model calls | Failed runs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| count_words | values | 3/3 | 100% | 100% | 100% | 4.0 | 0.3 |
| fibonacci | arithmetic | 2/3 | 100% | 0% | 67% | 3.3 | 0.7 |
| list_second | values | 3/3 | 100% | 100% | 100% | 7.3 | 3.3 |
| record_update | values | 2/3 | 100% | 0% | 67% | 2.3 | 0.0 |

## By tag

| Tag | Tasks | Pass rate | 95% CI |
| --- | --- | --- | --- |
| values | 3 | 89% | 67%–100% |
| arithmetic | 1 | 67% | insufficient tasks |

## Failing checks

- **fibonacci** computes 17710 (1×): no program computed 17710, no program computed a value
- **record_update** computes {age: 37, name: "Ada"} (1×): no program computed {age: 37, name: "Ada"}, no program computed a value
