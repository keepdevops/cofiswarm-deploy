# cofiswarm-deploy

Cofiswarm component: `deploy`.

- Layout: [REPO-STANDARD-LAYOUT](https://github.com/keepdevops/cofiswarmdev/blob/main/docs/REPO-STANDARD-LAYOUT.md)
- Migration: [MIGRATION-SPRINTS](https://github.com/keepdevops/cofiswarmdev/blob/main/docs/MIGRATION-SPRINTS.md)

## FHS paths

| Path | Purpose |
|------|---------|
| `/etc/cofiswarm/deploy/` | config |
| `/var/lib/cofiswarm/deploy/` | state |
| `/var/log/cofiswarm/deploy/` | logs |

## Test

```bash
./test/scripts/assert-layout.sh deploy
```
