# cofiswarm-deploy

Stack orchestration — FHS config render + compose profiles + host service launcher.

## Quick start

```bash
cp .env.example .env
make render-config
make compose-config
make stack-up      # docker pgvector + host Go services
make stack-down
```

## FHS mounts (Sprint 13)

| Host path | Consumers |
|-----------|-----------|
| `~/cofiswarm/fhs/etc/cofiswarm` | all services (`:ro` in compose) |
| `~/cofiswarm/fhs/var/lib/cofiswarm` | dispatch, rag, slot-manager, models |
| `~/cofiswarm/fhs/var/log/cofiswarm` | infer, agent_logs |
| `~/cofiswarm/fhs/run/cofiswarm` | zmq-bridge, host service PIDs |

## Profiles

| Profile | Compose | Host infer |
|---------|---------|------------|
| `8gb` | pgvector | gemma2b (scout) |
| `16gb` | pgvector + ui stub | full server_groups |
| `32gb` | pgvector + ui stub | full roster |

Gate: `make test` → SCALE-0 (`test/gates/SCALE-0.md`).
