# Contributing & Branching Strategy

## Branch Convention

| Branch | Purpose |
|---|---|
| `main` | Deployed state — always matches what runs on the server |
| `dev/{feature}` | New phases or features (e.g., `dev/phase6-vpn`) |
| `fix/{issue}` | Bug fixes (e.g., `fix/pihole-dns-timeout`) |

## Workflow

1. Branch from main: `git checkout -b dev/phase6-vpn`
2. Work, commit, push branch
3. When validated, merge to main: `git checkout main && git merge dev/phase6-vpn`
4. Tag the release: `git tag -a v1.1-phase6 -m "Phase 6: VPN access"`
5. Push: `git push origin main --tags`
6. Delete branch: `git branch -d dev/phase6-vpn`

## Tagging Convention

Format: `v{major}.{minor}-{phase-or-milestone}`

| Tag | Milestone |
|---|---|
| v0.1-initial | Initial commit |
| v0.2-phase1-2 | Foundation + Infrastructure |
| v0.5-phase3 | Core services (Samba, Jellyfin) |
| v0.8-phase4 | Photo management (Immich) |
| v1.0-phase5 | Wiki.js + Ollama + Open WebUI |
