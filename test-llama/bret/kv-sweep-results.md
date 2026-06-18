# KV-cache quantization sweep

Model: `Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf`  •  bench pp512/tg128 reps=3, fa=on  •  mem ctx=8192
Date: 2026-06-17

| KV type | prefill t/s | gen t/s | KV mem (GiB) | perplexity |
|---------|------------:|--------:|-------------:|-----------:|
| f16     |      583.61 |    53.7 |         1.00 |        — |
| q8_0    |      576.87 |   50.15 |         0.53 |        — |
| q4_0    |       576.9 |   50.21 |         0.28 |        — |
