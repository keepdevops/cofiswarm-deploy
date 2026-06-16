ROLE := deploy
.PHONY: test render-config compose-config up down ui-build stack-up stack-down test-scale0-gate
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
test-scale0-gate:
	./test/scripts/test-scale0-gate.sh

test-cutover-gate:
	./test/scripts/test-cutover-gate.sh
test-scale0-probe:
	./test/scripts/test-scale0-probe.sh
test-ui-api-gate:
	./test/scripts/test-ui-api-gate.sh
