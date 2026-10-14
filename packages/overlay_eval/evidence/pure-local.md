# Local pure-model check

Run on 2026-10-14 against the official Qwen3 0.6B Q8_0 model on a local
OpenAI-compatible llama.cpp server. One request was made, using the current
shared Overlay instructions, run tool, syntax and builtin guides. The expected
answer was not sent. No credentials or remote model service were used.

```sh
cd packages/overlay_eval
gleam run -m overlay/eval/pure -- openai-local:qwen3-0.6b
```

Actual result:

```text
FAIL: expected exactly one run tool call
```

Exit status was **1**. No program was graded because the reply did not satisfy
the tool-call contract. This checks a real response and the rejection path; it
does not demonstrate this model solving the task or estimate reliability.
The offline suite separately verifies an EYG program returning 17710 and
rejects wrong values, prose, effects, references and divergence.

Reproduction inputs:

- Model: [Qwen/Qwen3-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF),
  revision `23749fefcc72300e3a2ad315e1317431b06b590a`.
- File `Qwen3-0.6B-Q8_0.gguf`: 639446688 bytes, verified SHA-256
  `9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031`.
- Server: `ghcr.io/ggml-org/llama.cpp@sha256:89f180f16f295ee496fe00924ec2118cae2efec519d1a82c605420af09d2a6df`.
- Options: `--alias qwen3-0.6b --ctx-size 8192 --parallel 1 --threads 2
  --threads-batch 2 --n-predict 1024 --reasoning off --cache-type-k q4_0
  --cache-type-v q4_0 --flash-attn on`. Port 7210 was bound to loopback.
- Container limits: 900 MiB, no swap and two CPUs. The server reported
  288616.83 ms for 5439 tokens including prompt and generation; these are
  server measurements, not a latency benchmark.

The server was stopped after the check. A new run can produce a different
answer; model generation was not replaced with a scripted response.
