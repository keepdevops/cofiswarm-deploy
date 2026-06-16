ROLE := deploy
.PHONY: test render-config compose-config up down ui-build stack-up stack-down test-scale0-gate test-mode-relay-gate test-configure-gate test-configure-live build-dispatch build-modes build-configure test-scale0-signoff-gate render-scale0-signoff test-scale1-gate test-scale2-gate test-scale2-signoff-gate render-scale2-signoff test-architect-stream-gate test-architect-stream-pipeline-gate install-launchd test-scale4-gate test-scale4-signoff-gate render-scale4-signoff test-scale5-gate test-scale5-signoff-gate render-scale5-signoff test-scale6-gate test-scale6-signoff-gate render-scale6-signoff test-scale7-gate test-scale7-signoff-gate test-scale7-stream-signoff render-scale7-signoff test-ui-api-gate test-ui-stream-gate
test: test-standalone-layout test-scale0-gate test-cutover-gate
test-standalone-layout:
	./test/scripts/assert-layout.sh $(ROLE)
render-config:
	./scripts/render-config.sh
compose-config:
	@set -a && [ -f .env ] && . ./.env; set +a; \
	export COFISWARM_FHS_ROOT="$${COFISWARM_FHS_ROOT:-$$HOME/cofiswarm/fhs}"; \
	docker compose -f compose/stack.yml -f compose/profiles/$${COFISWARM_PROFILE:-16gb}.yml \
	  --profile $${COFISWARM_PROFILE:-16gb} config >/dev/null && echo ok: compose config
ui-build:
	@set -a && [ -f .env ] && . ./.env; set +a; \
	export COFISWARM_REPOS_ROOT="$${COFISWARM_REPOS_ROOT:-$$HOME/cofiswarm/repos}"; \
	export COFISWARM_REPOS_ROOT="$${COFISWARM_REPOS_ROOT/#\~\/$$HOME}"; \
	docker compose -f compose/stack.yml -f compose/profiles/$${COFISWARM_PROFILE:-16gb}.yml \
	  --profile $${COFISWARM_PROFILE:-16gb} build ui
up: stack-up
down: stack-down
stack-up:
	./scripts/stack-up.sh
stack-down:
	./scripts/stack-down.sh
GO ?= $(HOME)/.local/go/bin/go
# Pure Go services — avoid mlx-env CC=/opt/homebrew/opt/llvm/bin/clang when LLVM is absent
build-dispatch:
	cd "$(or $(COFISWARM_REPOS_ROOT),$(HOME)/cofiswarm/repos)/cofiswarm-dispatch" && \
	  CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-dispatch ./cmd/cofiswarm-dispatch
build-modes:
	@set -e; repos="$(or $(COFISWARM_REPOS_ROOT),$(HOME)/cofiswarm/repos)"; \
	for m in mode-flat mode-pipeline mode-cascade mode-router; do \
	  echo "==> $$m"; \
	  (cd "$$repos/cofiswarm-$$m" && CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-$$m ./cmd/cofiswarm-$$m); \
	done
build-configure:
	cd "$(or $(COFISWARM_REPOS_ROOT),$(HOME)/cofiswarm/repos)/cofiswarm-launcher" && \
	  CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-configure ./cmd/cofiswarm-configure
test-scale0-gate:
	./test/scripts/test-scale0-gate.sh

test-cutover-gate:
	./test/scripts/test-cutover-gate.sh
test-scale0-probe:
	./test/scripts/test-scale0-probe.sh
test-scale0-workload:
	./test/scripts/test-scale0-workload.sh
test-scale0-full:
	./test/scripts/test-scale0-full.sh
test-scale0-signoff-gate:
	./test/scripts/test-scale0-signoff-gate.sh
render-scale0-signoff:
	./test/scripts/render-scale0-signoff.sh
test-scale1-gate:
	./test/scripts/test-scale1-gate.sh
test-scale2-gate:
	./test/scripts/test-scale2-gate.sh
test-architect-stream-gate:
	./test/scripts/test-architect-stream-gate.sh
test-architect-stream-pipeline-gate:
	./test/scripts/test-architect-stream-pipeline-gate.sh
test-architect-stream-router-gate:
	./test/scripts/test-architect-stream-router-gate.sh
test-scale3-gate:
	./test/scripts/test-scale3-gate.sh
test-scale3-signoff-gate:
	./test/scripts/test-scale3-signoff-gate.sh
render-scale3-signoff:
	./test/scripts/render-scale3-signoff.sh
test-architect-stream-cascade-gate:
	./test/scripts/test-architect-stream-cascade-gate.sh
test-scale4-gate:
	./test/scripts/test-scale4-gate.sh
test-scale4-signoff-gate:
	./test/scripts/test-scale4-signoff-gate.sh
render-scale4-signoff:
	./test/scripts/render-scale4-signoff.sh
test-scale5-gate:
	./test/scripts/test-scale5-gate.sh
test-scale5-signoff-gate:
	./test/scripts/test-scale5-signoff-gate.sh
render-scale5-signoff:
	./test/scripts/render-scale5-signoff.sh
test-scale6-gate:
	./test/scripts/test-scale6-gate.sh
test-scale6-signoff-gate:
	./test/scripts/test-scale6-signoff-gate.sh
render-scale6-signoff:
	./test/scripts/render-scale6-signoff.sh
test-scale7-gate:
	./test/scripts/test-scale7-gate.sh
test-scale7-signoff-gate:
	./test/scripts/test-scale7-signoff-gate.sh
test-scale7-stream-signoff:
	./test/scripts/test-scale7-stream-signoff.sh
render-scale7-signoff:
	./test/scripts/render-scale7-signoff.sh
test-scale2-signoff-gate:
	./test/scripts/test-scale2-signoff-gate.sh
render-scale2-signoff:
	./test/scripts/render-scale2-signoff.sh
install-launchd:
	./scripts/install-launchd.sh
test-mode-relay-gate:
	./test/scripts/test-mode-relay-gate.sh
test-configure-gate:
	./test/scripts/test-configure-gate.sh
test-configure-live:
	./test/scripts/test-configure-live.sh
test-ui-api-gate:
	./test/scripts/test-ui-api-gate.sh
test-ui-stream-gate:
	./test/scripts/test-ui-stream-gate.sh
