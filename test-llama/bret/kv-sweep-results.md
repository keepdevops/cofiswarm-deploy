# KV-cache quantization sweep

Model: `Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf`  •  bench pp512/tg128 reps=3, fa=on  •  mem ctx=8192
Date: 2026-06-17

| KV type | prefill t/s | gen t/s | KV mem (GiB) | perplexity |
|---------|------------:|--------:|-------------:|-----------:|
| f16     |   876926597 |     n/a |         1.00 |        — |
| q8_0    |   888232708 |     n/a |         0.53 |        — |
| q4_0    |   886362819 |     n/a |         0.28 |        — |
