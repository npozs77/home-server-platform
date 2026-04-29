# Data Storage Structure

## Overview

Data storage organization across two LUKS-encrypted partitions:
- `/mnt/data/` — Primary data partition (NVMe, `/dev/nvme0n1p3`). User data, media, service data.
- `/mnt/backup/` — DAS backup partition (`/dev/sdb2`, ~900GB). Backup destination for configs, Immich, and Wiki.js data.

## Directory Structure

```
/mnt/data/
├── media/                    # Curated media library (755, root:media)
│   ├── Movies/               # Movie library (2775, media:media)
│   ├── TV Shows/             # TV show library (2775, media:media)
│   └── Music/                # Music library (2775, media:media)
├── family/                   # Shared family folders (755, root:family)
│   ├── Documents/            # RW for all users (2775, root:family, setgid)
│   ├── Photos/               # RO for Standard_User, RW for Admin/Power (2770, root:family, setgid)
│   ├── Videos/               # RO for Standard_User, RW for Admin/Power (2770, root:family, setgid)
│   └── Projects/             # RW for all users (2775, root:family, setgid)
├── users/                    # Personal user folders (755, root:root)
│   └── {username}/           # Personal folder (770, {username}:family)
│       ├── Documents/        # Personal documents (770, {username}:family)
│       ├── Photos/           # Personal photos (770, {username}:family)
│       ├── Videos/           # Personal videos (770, {username}:family)
│       ├── Music/            # Personal music (770, {username}:family)
│       └── .recycle/         # Recycle bin (770, {username}:family)
│           └── {username}/   # User-specific recycle bin
├── backups/                  # Backup storage (700, root:root)
│   ├── snapshots/            # Hourly/daily snapshots (700, root:root)
│   ├── incremental/          # Daily incremental backups (700, root:root)
│   └── offsite-sync/         # Weekly off-site sync staging (700, root:root)
└── services/                 # Service persistent data (755, root:root)
    ├── jellyfin/             # Jellyfin persistent data (755, root:root)
    │   ├── config/           # Jellyfin configuration (755, root:root)
    │   └── cache/            # Jellyfin transcoding cache (755, root:root)
    └── immich/               # Immich photo management data (755, root:root)
        ├── postgres/         # PostgreSQL data via DB_DATA_LOCATION (700, 999:999 — postgres container user)
        └── upload/           # Immich data root via UPLOAD_LOCATION → /data (755, root:root)
            ├── backups/      # Immich auto DB backups
            ├── encoded-video/  # Transcoded video files
            ├── library/      # ← ORIGINALS stored here (Storage Template)
            │   ├── admin/    # Admin user (storage label = "admin")
            │   │   └── YYYY/YYYY-MM-DD/  # Date-organized originals
            │   └── {user_uuid}/  # Regular user (storage label = UUID)
            │       └── YYYY/YYYY-MM-DD/  # Date-organized originals
            ├── profile/      # User profile photos
            ├── thumbs/       # Generated thumbnails
            └── upload/       # Staging directory (empty after processing)
```

## Top-Level Directories

### /mnt/data/media/
- **Purpose**: Curated media library for Jellyfin
- **Permissions**: 755 (root:media) - parent directory
- **Access**: Readable by all, writable by media group
- **Subdirectories**: Movies/ (2775, media:media), TV Shows/ (2775, media:media), Music/ (2775, media:media)
- **Created**: Phase 2, Task 2.1 (parent directory), Phase 3, Task 2.1 (subdirectories)
- **Note**: Subdirectories use setgid bit (2775) to ensure new files inherit media group

### /mnt/data/family/
- **Purpose**: Shared family folders
- **Permissions**: 755 (root:family) - parent directory
- **Access**: Readable by all, writable by family group
- **Subdirectories**: Documents/ (2775), Photos/ (2770), Videos/ (2770), Projects/ (2775)
- **Created**: Phase 2, Task 2.1 (parent directory), Phase 2, Task 2.2 (subdirectories)
- **Note**: Subdirectories use setgid bit to ensure new files inherit family group

### /mnt/data/users/
- **Purpose**: Personal user folders
- **Permissions**: 755 (root:root)
- **Access**: Readable by all, writable by root
- **Subdirectories**: Created during user provisioning (Phase 3)
- **Created**: Phase 2, Task 2.1 (parent directory), Phase 3, Task 5 (user subdirectories)

### /mnt/data/backups/
- **Purpose**: Backup storage
- **Permissions**: 700 (root:root)
- **Access**: Root-only
- **Subdirectories**: snapshots/, incremental/, offsite-sync/
- **Created**: Phase 2, Task 2.1

### /mnt/data/services/
- **Purpose**: Service persistent data
- **Permissions**: 755 (root:root)
- **Access**: Readable by all, writable by root
- **Subdirectories**: jellyfin/ (Phase 3), immich/ (Phase 4), wiki/, etc. (future phases)
- **Created**: Phase 2, Task 2.1

## Media Subdirectories

### /mnt/data/media/Movies/
- **Purpose**: Movie library for Jellyfin
- **Permissions**: 2775 (media:media) - setgid bit ensures group inheritance
- **Access**: Readable by all, writable by media group
- **Use Cases**: Movie files organized by title and year
- **Created**: Phase 3, Task 2.1

### /mnt/data/media/TV Shows/
- **Purpose**: TV show library for Jellyfin
- **Permissions**: 2775 (media:media) - setgid bit ensures group inheritance
- **Access**: Readable by all, writable by media group
- **Use Cases**: TV show files organized by series and season
- **Created**: Phase 3, Task 2.1

### /mnt/data/media/Music/
- **Purpose**: Music library for Jellyfin
- **Permissions**: 2775 (media:media) - setgid bit ensures group inheritance
- **Access**: Readable by all, writable by media group
- **Use Cases**: Music files organized by artist and album
- **Created**: Phase 3, Task 2.1

## Service Subdirectories

### /mnt/data/services/jellyfin/
- **Purpose**: Jellyfin persistent data
- **Permissions**: 755 (root:root)
- **Access**: Readable by all, writable by root
- **Subdirectories**: config/, cache/
- **Created**: Phase 3, Task 2.2

### /mnt/data/services/jellyfin/config/
- **Purpose**: Jellyfin configuration and metadata
- **Permissions**: 755 (root:root)
- **Access**: Readable by all, writable by root
- **Use Cases**: Jellyfin settings, library metadata, user data
- **Created**: Phase 3, Task 2.2

### /mnt/data/services/jellyfin/cache/
- **Purpose**: Jellyfin transcoding cache
- **Permissions**: 755 (root:root)
- **Access**: Readable by all, writable by root
- **Use Cases**: Temporary transcoded media files
- **Created**: Phase 3, Task 2.2

### /mnt/data/services/immich/
- **Purpose**: Immich photo management persistent data
- **Permissions**: 755 (root:root)
- **Access**: Readable by all, writable by root
- **Subdirectories**: postgres/, upload/
- **Created**: Phase 4, Task 3.1
- **Note**: model-cache uses a named Docker volume (managed by Docker, not a host directory)

### /mnt/data/services/immich/postgres/
- **Purpose**: PostgreSQL database data (user accounts, photo metadata, face recognition data)
- **Permissions**: 700 (999:999 — postgres container user)
- **Access**: PostgreSQL process inside container only
- **Use Cases**: Immich metadata, user accounts, face recognition vectors, album data
- **Created**: Phase 4, Task 3.1
- **Backup**: pg_dump only (NOT filesystem copy — see docs/09-immich-setup.md)
- **Docker Mount**: DB_DATA_LOCATION → /var/lib/postgresql/data

### /mnt/data/services/immich/upload/
- **Purpose**: Immich data root (uploads, library originals, thumbnails, encoded video)
- **Permissions**: 755 (root:root)
- **Access**: Immich server container (read-write), Samba container (read-only via library/ subdirectory)
- **Use Cases**: Photos uploaded from mobile apps, per-user photo storage organized by date
- **Created**: Phase 4, Task 3.1
- **Docker Mount**: UPLOAD_LOCATION → /data in immich-server container
- **Samba Mount**: Read-only mount in Samba container for per-user upload shares (library/ subdirectory)
- **Structure**: Immich v2 with Storage Template stores originals in `library/{storage_label}/YYYY/YYYY-MM-DD/filename.ext` where storage_label is "admin" for the admin user and the user's UUID for regular users. The `upload/` subdirectory inside is a staging area (empty after processing).

## Backup Subdirectories

### /mnt/data/family/Documents/
- **Purpose**: Shared documents (RW for all users)
- **Permissions**: 2775 (root:family) - setgid bit ensures group inheritance
- **Access**: Family group can read/write
- **Use Cases**: Shared PDFs, spreadsheets, text files
- **Created**: Phase 2, Task 2.2

### /mnt/data/family/Photos/
- **Purpose**: Family photo collection (RO for Standard_User, RW for Admin/Power)
- **Permissions**: 2770 (root:family) - setgid bit ensures group inheritance
- **Access**: Family group can read/write, others no access
- **Use Cases**: Family photos, albums, events
- **Created**: Phase 2, Task 2.2

### /mnt/data/family/Videos/
- **Purpose**: Family video collection (RO for Standard_User, RW for Admin/Power)
- **Permissions**: 2770 (root:family) - setgid bit ensures group inheritance
- **Access**: Family group can read/write, others no access
- **Use Cases**: Family videos, recordings, home movies
- **Created**: Phase 2, Task 2.2

### /mnt/data/family/Projects/
- **Purpose**: Shared projects (RW for all users)
- **Permissions**: 2775 (root:family) - setgid bit ensures group inheritance
- **Access**: Family group can read/write
- **Use Cases**: Collaborative projects, shared work
- **Created**: Phase 2, Task 2.2

## User Personal Folders

### /mnt/data/users/{username}/
- **Purpose**: Personal folder for individual user
- **Permissions**: 770 ({username}:family)
- **Access**: Owner can read/write, family group can read/write, others no access
- **Subdirectories**: Documents/, Photos/, Videos/, Music/, .recycle/{username}/
- **Created**: Phase 3, Task 5 (during user provisioning)
- **Note**: Samba container requires PGID=family to access these directories

### /mnt/data/users/{username}/Documents/
- **Purpose**: Personal documents
- **Permissions**: 770 ({username}:family)
- **Access**: Owner can read/write, family group can read/write
- **Use Cases**: Personal PDFs, spreadsheets, text files
- **Created**: Phase 3, Task 5 (during user provisioning)

### /mnt/data/users/{username}/Photos/
- **Purpose**: Personal photo collection
- **Permissions**: 770 ({username}:family)
- **Access**: Owner can read/write, family group can read/write
- **Use Cases**: Personal photos, camera uploads
- **Created**: Phase 3, Task 5 (during user provisioning)

### /mnt/data/users/{username}/Videos/
- **Purpose**: Personal video collection
- **Permissions**: 770 ({username}:family)
- **Access**: Owner can read/write, family group can read/write
- **Use Cases**: Personal videos, recordings
- **Created**: Phase 3, Task 5 (during user provisioning)

### /mnt/data/users/{username}/Music/
- **Purpose**: Personal music collection
- **Permissions**: 770 ({username}:family)
- **Access**: Owner can read/write, family group can read/write
- **Use Cases**: Personal music files, playlists
- **Created**: Phase 3, Task 5 (during user provisioning)

### /mnt/data/users/{username}/.recycle/{username}/
- **Purpose**: Recycle bin for deleted files from personal share
- **Permissions**: 770 ({username}:family)
- **Access**: Owner can read/write, family group can read/write
- **Retention**: 30 days (configurable)
- **Created**: Phase 3, Task 5 (during user provisioning)

## Backup Subdirectories

### /mnt/data/backups/snapshots/
- **Purpose**: Hourly/daily snapshots for quick recovery
- **Permissions**: 700 (root:root)
- **Access**: Root-only
- **Retention**: 48 hours of snapshots
- **Technology**: Btrfs or ZFS snapshots
- **Created**: Phase 2, Task 2.3

### /mnt/data/backups/incremental/
- **Purpose**: Daily incremental backups to external drive
- **Permissions**: 700 (root:root)
- **Access**: Root-only
- **Retention**: 30 days
- **Technology**: rsync or restic
- **Created**: Phase 2, Task 2.3

### /mnt/data/backups/offsite-sync/
- **Purpose**: Weekly off-site sync staging
- **Permissions**: 700 (root:root)
- **Access**: Root-only
- **Retention**: 12 weeks
- **Technology**: Manual or automated sync to cloud/external location
- **Created**: Phase 2, Task 2.3

## Permission Strategy

### Permission Levels
- **755**: Readable by all, writable by owner (top-level directories)
- **775**: Readable/writable by group, readable by others (shared documents)
- **770**: Readable/writable by group, no access for others (restricted family content)
- **700**: Owner-only access (backups, sensitive data)

### Group Membership
- **family**: All family users (Admin, Power User, Standard User)
- **media**: Users who can manage media library (Admin, Power User)
- **docker**: Users who can manage Docker containers (Admin, Power User)

## Access Patterns

### Admin User
- Full access to all directories
- Can modify permissions and ownership
- Can access backups

### Power User
- Read/write access to family/ (all subdirectories)
- Read/write access to media/
- Read/write access to own user/ folder
- No access to backups/

### Standard User
- Read/write access to family/Documents/ and family/Projects/
- Read-only access to family/Photos/ and family/Videos/
- Read-only access to media/
- Read/write access to own user/ folder
- No access to backups/

## Backup Strategy

### What Gets Backed Up
- All of /mnt/data/ (user data, media, service data)
- Configuration files from /opt/homeserver/configs/ (via Git)
- System configuration from /etc/homeserver/ (not in Git)

### What Doesn't Get Backed Up
- Docker images (can be re-pulled)
- Temporary files and caches
- Log files (rotated and compressed)

### Backup Schedule
- **Snapshots**: Hourly (last 48 hours)
- **Incremental**: Daily at 2 AM (last 30 days)
- **Off-site**: Weekly on Sunday at 3 AM (last 12 weeks)

## DAS Backup Partition (/mnt/backup/)

### Overview

External DAS (Direct Attached Storage) with ~900GB LUKS-encrypted partition used as the primary backup destination. Mounted manually or via cron (not auto-mounted at boot — `nofail,noauto` in crypttab).

### Encryption

- **Device**: `/dev/sdb2`
- **LUKS mapper**: `backup_crypt` → `/dev/mapper/backup_crypt`
- **Filesystem**: ext4
- **Mount point**: `/mnt/backup/`
- **Key slots**: Slot 0 = passphrase, Slot 1 = `/root/.luks-key` (same key file as data partition)
- **crypttab**: `backup_crypt UUID=<uuid> /root/.luks-key luks,nofail,noauto`
- **fstab**: `/dev/mapper/backup_crypt /mnt/backup ext4 defaults,nofail 0 2`

### Directory Structure

```
/mnt/backup/                          # LUKS-encrypted DAS partition (root:root, 755)
├── configs/                          # Server configuration backup (root:root, 755)
│   ├── homeserver/                   # Mirror of /opt/homeserver/
│   │   ├── configs/                  # foundation.env, services.env, secrets.env, etc.
│   │   └── scripts/                  # All deployment and operational scripts
│   └── system/                       # Individual system config files
│       ├── fstab
│       ├── crypttab
│       ├── sshd_config
│       ├── msmtp*                    # msmtp config files
│       ├── homeserver-*              # logrotate configs
│       └── luks-header-backup-*.img  # LUKS header backups (both partitions)
├── immich/                           # Immich backup (root:root, 755)
│   ├── immich-db-YYYYMMDD_HHMMSS.sql # Timestamped DB dumps (30-day retention)
│   ├── upload/                       # rsync mirror of Immich uploads
│   ├── media-photos/                 # rsync mirror of media photos
│   └── family-photos/               # rsync mirror of family photos
└── wiki/                             # Wiki.js backup (root:root, 755)
    ├── wiki-db-YYYYMMDD_HHMMSS.sql   # Timestamped DB dumps (30-day retention)
    └── data/                         # rsync mirror of wiki data directory
```

### Ownership and Permissions

- All directories: `root:root`, `755`
- All backup operations run as root (via cron or sudo)
- LUKS header backup files: `root:root`, `600`

### Subdirectory Details

| Directory | Purpose | Backup Script | Sync Method |
|-----------|---------|---------------|-------------|
| `configs/homeserver/` | Mirror of `/opt/homeserver/configs/` and `scripts/` | `backup-configs.sh` | `rsync -a --delete` |
| `configs/system/` | System config files (fstab, crypttab, sshd, msmtp, logrotate, LUKS headers) | `backup-configs.sh` | File copy |
| `immich/` | Immich database dumps + photo/upload mirrors | `backup-immich.sh` | `pg_dump` + `rsync -a --delete` |
| `wiki/` | Wiki.js database dumps + data mirror | `backup-wiki.sh` | `pg_dump` + `rsync -a --delete` (stub until Wiki.js deployed) |

### Manual Mount/Unmount

```bash
# Open and mount
sudo cryptsetup luksOpen /dev/sdb2 backup_crypt
sudo mount /dev/mapper/backup_crypt /mnt/backup

# Unmount and close
sudo umount /mnt/backup
sudo cryptsetup luksClose backup_crypt
```

### LUKS Header Backups

Stored at `/root/` with 600 permissions and also copied to `/mnt/backup/configs/system/`:
- `/root/luks-header-backup-sdb2.img` — Backup partition header
- `/root/luks-header-backup-nvme0n1p3.img` — Data partition header

See `docs/12-runbooks.md` → LUKS Disk Encryption Recovery for recovery procedures.

## DAS Power Management

### Disk Spindown

Both DAS disks are configured to spin down after 10 minutes idle via `hdparm`.

| Disk | Device | Size | Use | Spindown | APM |
|------|--------|------|-----|----------|-----|
| Backup | sdb (`usb-TerraMas_TDAS_WKPSM2W8`) | 1TB | LUKS backup partition | 10 min | 127 |
| Future | sdc (`usb-TerraMas_TDAS_WSC30NR9`) | 8TB | Unmounted (future use) | 10 min | N/A |

Config persisted in `/etc/hdparm.conf`. Applied automatically on boot.

### What Wakes the Disks

- Daily backup at 02:00 (`backup-all.sh` writes to `/mnt/backup`)
- Any manual access to `/mnt/backup`

### What Does NOT Wake the Disks

- Container health check (only runs `docker inspect`)
- `mountpoint -q` check (kernel-level, no block I/O)

### Fan Behavior

The D4-320 fan is hardware-controlled and runs whenever the enclosure is powered. `hdparm` controls disk spindown only, not the fan.

### Check Status / Re-apply

```bash
# Check current disk power state
sudo bash /opt/homeserver/scripts/operations/das-power-management.sh status

# Re-apply spindown settings (if needed after reboot issues)
sudo bash /opt/homeserver/scripts/operations/das-power-management.sh apply
```

## Related Documentation

- Architecture Overview: docs/00-architecture-overview.md
- Foundation Layer: docs/01-foundation-layer.md
- Infrastructure Layer: docs/02-infrastructure-layer.md
- Immich Setup: docs/09-immich-setup.md
- Runbooks (LUKS Recovery): docs/12-runbooks.md
- Phase 2 Spec: .kiro/specs/02-infrastructure/
- Phase 4 Spec: .kiro/specs/04-photo-management/
