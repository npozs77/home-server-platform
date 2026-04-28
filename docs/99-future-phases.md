# Future Phases Roadmap

**Status**: Planning - Not yet implemented  
**Last Updated**: 2026-03-02

## Overview

This document outlines planned future phases for the home media server platform. These phases build on the completed foundation (Phase 1), infrastructure (Phase 2), and core services (Phase 3).

## Deployment Status

### Completed Phases

- ✅ Phase 1: Foundation Layer (system hardening, LUKS encryption, Git repository)
- ✅ Phase 2: Infrastructure Layer (Caddy, DNS, monitoring, SMTP)
- ✅ Phase 3: Core Services (Jellyfin media streaming, Samba file sharing)

### Future Phases

- ⏳ Phase 4: Photo Management Services
- ⏳ Phase 5: Family Wiki
- ⏳ Phase 6: Home Automation
- ⏳ Phase 7: Advanced Features

---

## Phase 4: Photo Management Services

**Purpose**: Automatic photo backup from mobile devices and AI-powered photo organization

### Service

**Immich** (Photo Cloud + Mobile Backup)
- Mobile apps (iOS/Android) for automatic photo backup
- Web interface for viewing and organizing photos
- Per-user libraries + shared family library
- Face recognition and AI-powered search
- Timeline, albums, and advanced search
- Access: `https://photos.home.mydomain.com`

**Note**: Immich handles both mobile backup AND photo organization - no need for a second service.

### Key Features

- Automatic background upload from phones
- Per-user private photo libraries
- Shared family photo library
- AI face recognition and tagging
- Duplicate detection
- RAW photo support
- Mobile and web access

### Storage Structure

```
/mnt/data/
├── users/
│   ├── user1/Photos/     # Personal photos (auto-uploaded from phone)
│   ├── user2/Photos/
│   └── user3/Photos/
└── family/Photos/        # Shared family photos
```

### Dependencies

- Postgres (Immich database)
- Redis (Immich cache)

### Reference

- OLD specs: `OLD.KIRO/OLD/specs/06-media-services/`

---

## Phase 5: Family Wiki

**Purpose**: Centralized family knowledge base and documentation

### Service

**Wiki.js**
- Modern wiki with visual editor
- Git-backed content storage
- User authentication and permissions
- Search and organization
- Access: `https://wiki.home.mydomain.com`

### Key Features

- Family documentation (recipes, guides, procedures)
- Project documentation
- Meeting notes and planning
- Visual editor (no markdown required)
- Version control (Git-backed)
- Search across all content

### Use Cases

- Family recipes and cooking guides
- Home maintenance procedures
- Project documentation
- Travel planning
- Gift ideas and wishlists

### Reference

- OLD specs: `OLD.KIRO/OLD/specs/05-wiki/`
- Design blueprint: `OLD/input_docs/family_wiki_design_blueprint.md`

---

## Phase 6: Home Automation

**Purpose**: Smart home control and automation

### Service

**Home Assistant**
- Smart home hub and automation platform
- Device integration (lights, sensors, cameras)
- Automation rules and scenes
- Mobile app for remote control
- Access: `https://ha.home.mydomain.com`

### Key Features

- Smart device control (lights, thermostats, locks)
- Automation rules (time-based, sensor-triggered)
- Energy monitoring
- Security camera integration
- Voice assistant integration
- Mobile notifications

### Integration Examples

- Automatic lights based on presence
- Temperature control schedules
- Security alerts
- Energy usage tracking

### Reference

- OLD specs: `OLD.KIRO/OLD/specs/07-home-assistant/`

---

## Phase 7: Advanced Features

**Purpose**: Enhanced functionality and lifecycle management

### Features

**Local AI Service**
- LocalAI (OpenAI-compatible API for local LLM inference)
- Open WebUI (ChatGPT-like interface for family)
- Replace ChatGPT/Copilot subscriptions with self-hosted AI
- Home Assistant integration for conversational assist
- CLI/API access for automations
- Access: `https://chat.home.mydomain.com` (UI), `https://ai.home.mydomain.com` (API)

**Container Lifecycle Management**
- On-demand container start (start on first access)
- Idle shutdown (stop after inactivity)
- Automated container upgrades (pull, recreate, health check, rollback on failure)
- Resource optimization
- Health monitoring

**Enhanced Backups**
- Automated off-site backups (Proton Drive, cloud storage)
- Backup verification and testing
- Disaster recovery procedures
- Backup rotation policies

**Remote Access (Zero Trust)**
- Cloudflare Tunnel for secure remote access
- Identity-based authentication (no VPN)
- Access web services from anywhere (Wiki, Immich, Home Assistant, Jellyfin)
- SSH access via Cloudflare Access
- No exposed home IP or port forwarding
- Outbound-only connections from home server

**Note**: Replaces traditional VPN with modern Zero Trust approach - simpler, more secure, no router configuration needed.

**Additional Services**
- Local AI service (LocalAI + Open WebUI)
- Git server (self-hosted Git repositories)
- Password manager (Vaultwarden/Bitwarden)
- RSS reader (FreshRSS)
- Download manager (qBittorrent)

### Reference

- OLD specs: `OLD.KIRO/OLD/specs/08-security-services/`

---

## Implementation Approach

### Phased Deployment

Each phase follows the same workflow:
1. Create spec (requirements → design → tasks)
2. Implement deployment scripts
3. Test and validate
4. Document in `docs/`
5. Commit to Git

### Prerequisites

Before starting a new phase:
- Previous phases must be complete and stable
- All validation checks passing
- Documentation up to date
- Git repository committed

### Estimated Timeline

- Phase 4 (Photo Services): 3-4 hours
- Phase 5 (Wiki): 2-3 hours
- Phase 6 (Home Automation): 4-6 hours
- Phase 7 (Advanced Features): 4-6 hours

Total: 13-19 hours additional work

---

## Priority Order

### High Priority (Next to Implement)

1. **Phase 4: Photo Management** - Addresses immediate need for phone photo backup
2. **Phase 5: Family Wiki** - Centralized documentation and knowledge sharing

### Medium Priority

3. **Phase 6: Home Automation** - Smart home control (if devices available)

### Low Priority (Future Enhancement)

4. **Phase 7: Advanced Features** - Optimization and additional services

---

## Related Documentation

- Platform overview: `docs/00-architecture-overview.md`
- Current deployment: `docs/01-foundation-layer.md`, `docs/02-infrastructure-layer.md`, `docs/03-services-layer.md`
- OLD specs (detailed): `OLD.KIRO/OLD/specs/`

---

**Note**: This is a high-level roadmap. Detailed specs will be created when each phase is ready for implementation.
