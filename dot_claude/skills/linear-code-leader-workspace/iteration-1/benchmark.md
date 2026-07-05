# Benchmark: linear-code-leader

Generated: 2026-05-18T16:14:21.340312+00:00

## Configuration summary

| Config | pass_rate (mean ± sd) | time_s (mean) | tokens (mean) |
|---|---|---|---|
| with_skill | 1.0 ± 0.0 | 485.2333 | 94725 |
| without_skill | 0.4444 ± 0.0 | 538.1033 | 98645 |

## Delta (with_skill − without_skill)
- pass_rate: +0.5556
- time_seconds: -52.87
- tokens: -3919.3333

## Per-run pass rates

| eval | config | pass | total | pass_rate | time_s | tokens |
|---|---|---|---|---|---|---|
| eval-1-typescript-framework | with_skill | 9 | 9 | 1.0 | 494.03 | 97650 |
| eval-1-typescript-framework | without_skill | 4 | 9 | 0.4444 | 637.08 | 106500 |
| eval-2-go-cli | with_skill | 9 | 9 | 1.0 | 473.06 | 93027 |
| eval-2-go-cli | without_skill | 4 | 9 | 0.4444 | 529.29 | 91630 |
| eval-3-python-library | with_skill | 9 | 9 | 1.0 | 488.61 | 93500 |
| eval-3-python-library | without_skill | 4 | 9 | 0.4444 | 447.94 | 97805 |