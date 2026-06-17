ROLE := deploy
.PHONY: test render-config compose-config up down ui-build stack-up stack-down test-scale0-gate test-mode-relay-gate test-configure-gate test-configure-live build-dispatch build-modes build-configure build-observer build-convert build-sidecars test-scale0-signoff-gate render-scale0-signoff test-scale1-gate test-scale2-gate test-scale2-signoff-gate render-scale2-signoff test-architect-stream-gate test-architect-stream-pipeline-gate install-launchd uninstall-launchd launchd-status test-scale4-gate test-scale4-signoff-gate render-scale4-signoff test-scale5-gate test-scale5-signoff-gate render-scale5-signoff test-scale6-gate test-scale6-signoff-gate render-scale6-signoff test-scale7-gate test-scale7-signoff-gate test-scale7-stream-signoff render-scale7-signoff test-ui-api-gate test-ui-stream-gate test-gateway-cleanup-gate test-ui-ops-gate test-stack-health-gate test-launchd-gate test-launchd-live-gate test-migration-ops-gate test-device-ops-signoff-gate render-device-ops-signoff ops-check test-ui-security-gate test-security-signoff-gate render-security-signoff security test-repos-schema-gate test-ci-static-gate test-ci-signoff-gate render-ci-signoff ci build-convert build-sidecars test-sidecars-gate test-sidecars-signoff-gate render-sidecars-signoff sidecars test-post-migration-signoff-gate render-post-migration-signoff post-migration post-migration-live repo-layout install-repo-ci test-repo-layout-gate test-repo-layout-signoff-gate render-repo-layout-signoff test-repos-pins-gate test-migration-signoff-gate render-migration-signoff pin-repos test-observer-ops-gate test-grafana-layout-gate test-observability-gate test-prometheus-metrics-gate test-prometheus-up-gate observability-up observability-down test-zmq-bridge-gate test-observability-signoff-gate render-observability-signoff test-release-signoff-gate render-release-signoff tag-release test-release-tag-gate release device-ops security ci sidecars go-ci mode-sdk-release tag-mode-sdk phase6 phase7 optional-repos release-cut tag-all-repos push-all-repos remote-push
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
	export GOWORK="$$repos/go.work"; \
	[[ -f "$$GOWORK" ]] || ./scripts/render-go-workspace.sh; \
	for m in mode-flat mode-pipeline mode-cascade mode-router; do \
	  echo "==> $$m"; \
	  (cd "$$repos/cofiswarm-$$m" && CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-$$m ./cmd/cofiswarm-$$m); \
	done
build-configure:
	cd "$(or $(COFISWARM_REPOS_ROOT),$(HOME)/cofiswarm/repos)/cofiswarm-launcher" && \
	  CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-configure ./cmd/cofiswarm-configure
build-observer:
	cd "$(or $(COFISWARM_REPOS_ROOT),$(HOME)/cofiswarm/repos)/cofiswarm-observer" && \
	  CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-observer ./cmd/cofiswarm-observer
build-convert:
	cd "$(or $(COFISWARM_REPOS_ROOT),$(HOME)/cofiswarm/repos)/cofiswarm-convert" && \
	  CGO_ENABLED=0 $(GO) build -o bin/cofiswarm-convert ./cmd/cofiswarm-convert
build-sidecars: build-convert
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
uninstall-launchd:
	./scripts/uninstall-launchd.sh
launchd-status:
	./scripts/launchd-status.sh
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
test-gateway-cleanup-gate:
	./test/scripts/test-gateway-cleanup-gate.sh
test-ui-ops-gate:
	./test/scripts/test-ui-ops-gate.sh
test-stack-health-gate:
	./test/scripts/test-stack-health-gate.sh
test-launchd-gate:
	./test/scripts/test-launchd-gate.sh
test-launchd-live-gate:
	./test/scripts/test-launchd-live-gate.sh
test-device-ops-signoff-gate:
	./test/scripts/test-device-ops-signoff-gate.sh
render-device-ops-signoff:
	DEVICE_OPS_SKIP_GATE=1 ./test/scripts/render-device-ops-signoff.sh
ops-check: test-stack-health-gate test-ui-ops-gate
test-migration-ops-gate:
	./test/scripts/test-migration-ops-gate.sh
pin-repos:
	./scripts/pin-repos.sh
test-repos-pins-gate:
	./test/scripts/test-repos-pins-gate.sh
test-migration-signoff-gate:
	./test/scripts/test-migration-signoff-gate.sh
render-migration-signoff:
	./test/scripts/render-migration-signoff.sh
test-observer-ops-gate:
	./test/scripts/test-observer-ops-gate.sh
test-grafana-layout-gate:
	./test/scripts/test-grafana-layout-gate.sh
test-observability-gate:
	./test/scripts/test-observer-ops-gate.sh
	./test/scripts/test-grafana-layout-gate.sh
	./test/scripts/test-prometheus-metrics-gate.sh
test-prometheus-metrics-gate:
	./test/scripts/test-prometheus-metrics-gate.sh
observability-up:
	@set -a && [ -f .env ] && . ./.env; set +a; \
	export COFISWARM_REPOS_ROOT="$${COFISWARM_REPOS_ROOT:-$$HOME/cofiswarm/repos}"; \
	export COFISWARM_DEPLOY_ROOT="$$(pwd)"; \
	docker compose -f compose/observability.yml up -d
observability-down:
	docker compose -f compose/observability.yml down
test-prometheus-up-gate:
	./test/scripts/test-prometheus-up-gate.sh
test-zmq-bridge-gate:
	./test/scripts/test-zmq-bridge-gate.sh
test-observability-signoff-gate:
	./test/scripts/test-observability-signoff-gate.sh
render-observability-signoff:
	./test/scripts/render-observability-signoff.sh
test-release-signoff-gate:
	./test/scripts/test-release-signoff-gate.sh
render-release-signoff:
	RELEASE_SKIP_GATE=1 ./test/scripts/render-release-signoff.sh
tag-release:
	./scripts/tag-release.sh
tag-all-repos:
	./scripts/tag-all-repos.sh
test-all-release-tags-gate:
	./test/scripts/test-all-release-tags-gate.sh
test-release-cut-signoff-gate:
	./test/scripts/test-release-cut-signoff-gate.sh
render-release-cut-signoff:
	RELEASE_CUT_SKIP_GATE=1 ./test/scripts/render-release-cut-signoff.sh
release-cut: tag-all-repos test-release-cut-signoff-gate render-release-cut-signoff
push-all-repos:
	./scripts/push-all-repos.sh
test-remote-sync-gate:
	./test/scripts/test-remote-sync-gate.sh
test-remote-push-signoff-gate:
	./test/scripts/test-remote-push-signoff-gate.sh
render-remote-push-signoff:
	REMOTE_PUSH_SKIP_GATE=1 ./test/scripts/render-remote-push-signoff.sh
remote-push: test-remote-push-signoff-gate render-remote-push-signoff
test-release-tag-gate:
	./test/scripts/test-all-release-tags-gate.sh
release: test-release-signoff-gate render-release-signoff tag-all-repos test-release-tag-gate
device-ops: test-device-ops-signoff-gate render-device-ops-signoff
test-ui-security-gate:
	./test/scripts/test-ui-security-gate.sh
test-security-signoff-gate:
	./test/scripts/test-security-signoff-gate.sh
render-security-signoff:
	SECURITY_SKIP_GATE=1 ./test/scripts/render-security-signoff.sh
security: test-security-signoff-gate render-security-signoff
test-repos-schema-gate:
	./test/scripts/test-repos-schema-gate.sh
test-ci-static-gate:
	./test/scripts/test-ci-static-gate.sh
test-ci-signoff-gate:
	./test/scripts/test-ci-signoff-gate.sh
render-ci-signoff:
	CI_SKIP_GATE=1 ./test/scripts/render-ci-signoff.sh
ci: test-ci-signoff-gate render-ci-signoff
test-sidecars-gate:
	./test/scripts/test-sidecars-gate.sh
test-sidecars-signoff-gate:
	./test/scripts/test-sidecars-signoff-gate.sh
render-sidecars-signoff:
	SIDECARS_SKIP_GATE=1 ./test/scripts/render-sidecars-signoff.sh
sidecars: test-sidecars-signoff-gate render-sidecars-signoff
test-post-migration-signoff-gate:
	./test/scripts/test-post-migration-signoff-gate.sh
render-post-migration-signoff:
	POST_MIGRATION_SKIP_GATE=1 ./test/scripts/render-post-migration-signoff.sh
post-migration: test-post-migration-signoff-gate render-post-migration-signoff
post-migration-live: pin-repos
	POST_MIGRATION_LIVE=1 $(MAKE) post-migration
install-repo-ci:
	./scripts/install-repo-ci.sh
test-repo-layout-gate:
	./test/scripts/test-repo-layout-gate.sh
test-repo-layout-signoff-gate:
	./test/scripts/test-repo-layout-signoff-gate.sh
render-repo-layout-signoff:
	REPO_LAYOUT_SKIP_GATE=1 ./test/scripts/render-repo-layout-signoff.sh
repo-layout: test-repo-layout-signoff-gate render-repo-layout-signoff
render-go-workspace:
	./scripts/render-go-workspace.sh
test-go-workspace-gate:
	./test/scripts/test-go-workspace-gate.sh
test-go-modules-signoff-gate:
	./test/scripts/test-go-modules-signoff-gate.sh
render-go-modules-signoff:
	GO_MODULES_SKIP_GATE=1 ./test/scripts/render-go-modules-signoff.sh
go-modules: render-go-workspace test-go-modules-signoff-gate render-go-modules-signoff
test-repo-ci-gate:
	./test/scripts/test-repo-ci-gate.sh
test-repo-ci-signoff-gate:
	./test/scripts/test-repo-ci-signoff-gate.sh
render-repo-ci-signoff:
	REPO_CI_SKIP_GATE=1 ./test/scripts/render-repo-ci-signoff.sh
repo-ci: test-repo-ci-signoff-gate render-repo-ci-signoff
test-go-ci-gate:
	./test/scripts/test-go-ci-gate.sh
test-go-ci-signoff-gate:
	./test/scripts/test-go-ci-signoff-gate.sh
render-go-ci-signoff:
	GO_CI_SKIP_GATE=1 ./test/scripts/render-go-ci-signoff.sh
go-ci: test-go-ci-signoff-gate render-go-ci-signoff
tag-mode-sdk:
	./scripts/tag-mode-sdk.sh
test-mode-sdk-release-gate:
	./test/scripts/test-mode-sdk-release-gate.sh
test-mode-sdk-release-signoff-gate:
	./test/scripts/test-mode-sdk-release-signoff-gate.sh
render-mode-sdk-release-signoff:
	MODE_SDK_RELEASE_SKIP_GATE=1 ./test/scripts/render-mode-sdk-release-signoff.sh
mode-sdk-release: tag-mode-sdk test-mode-sdk-release-signoff-gate render-mode-sdk-release-signoff
test-phase6-gate:
	./test/scripts/test-phase6-gate.sh
test-phase6-signoff-gate:
	./test/scripts/test-phase6-signoff-gate.sh
render-phase6-signoff:
	PHASE6_SKIP_GATE=1 ./test/scripts/render-phase6-signoff.sh
phase6: test-phase6-signoff-gate render-phase6-signoff
test-phase7-gate:
	./test/scripts/test-phase7-gate.sh
test-phase7-signoff-gate:
	./test/scripts/test-phase7-signoff-gate.sh
render-phase7-signoff:
	PHASE7_SKIP_GATE=1 ./test/scripts/render-phase7-signoff.sh
phase7: test-phase7-signoff-gate render-phase7-signoff
optional-repos: phase6 phase7
