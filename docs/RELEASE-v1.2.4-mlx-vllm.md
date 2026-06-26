# Release v1.2.4 — MLX + vLLM engine wiring

Runbook for shipping the multi-engine work (the modes can now run llama + mlx +
vllm agents through the shared `InferenceBackend` contract). Execute the phases
**in order** — there is one hard cross-repo dependency (mode-sdk → backend-vllm).

## PRs in this release

| Repo | PR | Branch | Depends on |
|------|----|--------|-----------|
| cofiswarm-dispatch | #16 | `fix/stream-stub-fail-loud` | — |
| cofiswarm-convert | #4 | `fix/convert-real-conversion` | — |
| cofiswarm-backend-llama | #4 | `fix/backend-llama-interface` | — |
| cofiswarm-backend-vllm | #2 | `feat/backend-vllm-implementation` | — |
| cofiswarm-deploy | #40 | `feat/self-sufficient-up` | — |
| cofiswarm-config | #6 | `feat/vllm-agent-schema` | — |
| **cofiswarm-mode-sdk** | **#3** | `feat/wire-mlx-backend` | **backend-vllm #2** |

> `REPOS=~/cofiswarm/repos` is assumed below. Merges use `gh pr merge --squash`;
> adjust to your merge policy.

---

## Phase 1 — Merge the independent PRs

No cross-repo dependency; merge in any order.

```bash
gh -R keepdevops/cofiswarm-dispatch     pr merge 16 --squash
gh -R keepdevops/cofiswarm-convert      pr merge 4  --squash
gh -R keepdevops/cofiswarm-backend-llama pr merge 4 --squash
gh -R keepdevops/cofiswarm-deploy       pr merge 40 --squash
gh -R keepdevops/cofiswarm-config       pr merge 6  --squash
```

## Phase 2 — backend-vllm first (mode-sdk depends on it)

```bash
gh -R keepdevops/cofiswarm-backend-vllm pr merge 2 --squash
# Capture the merge commit on main — mode-sdk re-pins to it.
BVLLM_SHA=$(gh -R keepdevops/cofiswarm-backend-vllm api repos/{owner}/{repo}/commits/main --jq .sha)
echo "backend-vllm main = $BVLLM_SHA"
```

## Phase 3 — Re-pin mode-sdk to the merged backend-vllm, then merge

mode-sdk currently pins backend-vllm at a **branch-commit** pseudo-version
(resolvable, but re-pin to the merge commit for hygiene). backend-mlx and
backend-sdk already use published pseudo-versions and need no change.

```bash
cd "$REPOS/cofiswarm-mode-sdk"
git checkout feat/wire-mlx-backend && git pull
GOFLAGS=-mod=mod GOWORK=off go get \
  github.com/keepdevops/cofiswarm-backend-vllm@"$BVLLM_SHA"
GOWORK=off go mod tidy
GOWORK=off go build ./... && GOWORK=off go test ./...
git commit -am "Re-pin backend-vllm to its merge commit"
git push
gh -R keepdevops/cofiswarm-mode-sdk pr merge 3 --squash
```

## Phase 4 — Tag mode-sdk v1.2.4

The `VERSION` file is already bumped to `v1.2.4` in PR #3 (it was stale at
`v0.1.0` — the known pin trap).

```bash
cd "$REPOS/cofiswarm-deploy"
make tag-mode-sdk                                   # reads mode-sdk/VERSION -> v1.2.4
git -C "$REPOS/cofiswarm-mode-sdk" push origin v1.2.4
```

## Phase 5 — Bump the four mode-* repos to mode-sdk v1.2.4

They currently `require cofiswarm-mode-sdk v1.2.3`. Bump, tidy, build, push.

```bash
cd "$REPOS"
for m in mode-flat mode-pipeline mode-cascade mode-router; do
  ( cd "cofiswarm-$m" \
    && GOFLAGS=-mod=mod GOWORK=off go get github.com/keepdevops/cofiswarm-mode-sdk@v1.2.4 \
    && GOWORK=off go mod tidy \
    && GOWORK=off go build ./... \
    && git commit -am "Bump cofiswarm-mode-sdk to v1.2.4 (mlx+vllm engines)" \
    && git push )
done
```

> The go.work workspace already resolves mode-sdk locally via `replace`, so the
> deploy's host-binary build (`make build-modes`) gets the new code immediately;
> this phase is what makes the **standalone / CI** builds of the mode-* repos
> pick it up.

## Phase 6 — Refresh repos.json pins + stamp the release

```bash
cd "$REPOS/cofiswarm-deploy"
RELEASE_VERSION=1.2.4 make pin-repos        # repos.json pins -> local HEADs, release -> v1.2.4
git commit -am "Pin repos to v1.2.4 (mlx+vllm)"
git push
```

## Phase 7 — Rebuild + smoke

```bash
cd "$REPOS/cofiswarm-deploy"
make build-all          # rebuild every host binary (incl. modes with v1.2.4)
make up                 # build-then-start the full stack
```

To actually run a vLLM agent, add one to the live roster (it is **not** added by
default — the running swarm is unchanged). Copy the template and rebuild config:

```bash
cp "$REPOS/cofiswarm-config/templates/agent-vllm.example.json" \
   "$REPOS/cofiswarm-config/config/agents/programmer-vllm.json"
( cd "$REPOS/cofiswarm-config" && bin/cofiswarm-config build )   # validates engine/model
make render-config                                               # push swarm-config to FHS
```

vLLM must be serving on `:12434` (Docker Model Runner) for that agent to be
healthy; MLX agents need `mlx_lm.server` on the host (Metal).

---

## Rollback

- mode-sdk tag is immutable once pushed; to revert, bump `VERSION` to `v1.2.5`
  with the offending change reverted and re-run Phases 3–6.
- `repos.json` pins are plain SHAs — `git revert` the Phase 6 commit to restore
  the previous release.

## Notes

- **Hard ordering:** only Phase 2 → 3 (mode-sdk needs backend-vllm merged).
  Everything else is independent and may be parallelised.
- **vllm dependency hygiene:** until backend-vllm #2 merges, mode-sdk resolves it
  from the implementation branch commit — valid but branch-scoped. Phase 3
  re-pins to `main`.
- **No schema drift:** the config build validates engine/model coherence
  (cofiswarm-config #6), so a malformed vllm agent fails `bin/cofiswarm-config
  build` rather than at inference time.
