# Native terminal comparison

Last trial recorded at 2026-10-15T03:49:27Z. Frontend revision: 022cc303e908d273955952090d256463ed3369ca.

Medians of five trial means and five trial p95s. Ranges show observed trial means, not confidence intervals.

| Workload | Rows | Frontend | Mean ms | p95 ms | Mean range ms | Mount ms | History ms |
|---|---:|---|---:|---:|---|---:|---:|
| stream | 20 | core | 7.95 | 13.54 | 7.62–8.38 | 24.13 | 51.37 |
| stream | 20 | lustre | 8.22 | 13.91 | 8.1–10.29 | 32.36 | 80.45 |
| stream | 20 | signals | 7.85 | 13.43 | 7.78–8.08 | 27.36 | 56.22 |
| stream | 200 | core | 14.46 | 19.93 | 13.94–14.72 | 23.41 | 245.32 |
| stream | 200 | lustre | 16.67 | 22.8 | 16.25–17.6 | 33.12 | 472.44 |
| stream | 200 | signals | 14.84 | 22.77 | 14.19–15.69 | 27.72 | 378.87 |
| typing | 20 | core | 1.53 | 3.33 | 1.49–1.69 | 25.11 | 30.89 |
| typing | 20 | lustre | 1.84 | 3.96 | 1.76–2.01 | 32.2 | 55.68 |
| typing | 20 | signals | 1.59 | 3.44 | 1.51–1.96 | 26.81 | 35.97 |
| typing | 200 | core | 2.49 | 5.02 | 2.33–2.58 | 24.23 | 256.19 |
| typing | 200 | lustre | 2.33 | 4.63 | 2.16–3.47 | 30.68 | 443.87 |
| typing | 200 | signals | 2.68 | 4.95 | 2.44–2.76 | 27.47 | 353.52 |
