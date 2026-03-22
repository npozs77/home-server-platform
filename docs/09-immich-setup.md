# Immich Setup Guide

## Initial Setup Wizard

1. Access https://photos.home.mydomain.com from browser
2. Create admin account (first user becomes administrator)
3. Set admin password (Immich-specific, not Linux password)
4. Generate API key: User Settings → API Keys → New API Key
5. Store API key in /opt/homeserver/configs/secrets.env as IMMICH_API_KEY

## User Account Creation

Users are provisioned automatically by the deployment script:
```bash
sudo ./scripts/deploy/tasks/task-ph4-05-provision-immich-users.sh
```

The script:
- Reads ADMIN_USER, POWER_USERS, STANDARD_USERS from config
- Creates Immich accounts via REST API (POST /api/users)
- Admin user: uses ADMIN_EMAIL from foundation.env (real email), isAdmin=true
- Other users: uses {username}@homeserver (placeholder email), isAdmin=false
- Captures UUIDs from API responses
- Writes IMMICH_UUID_{username} to services.env

## UUID Discovery Commands

```bash
# Via Immich API (preferred)
source /opt/homeserver/configs/secrets.env
curl -s -H "x-api-key: ${IMMICH_API_KEY}" \
  https://photos.home.mydomain.com/api/users | jq '.[] | {id, email, name}'

# Via PostgreSQL (fallback)
docker exec immich-postgres psql -U postgres -d immich \
  -c "SELECT id, email, name FROM users;"
```

## UUID-to-Username Mapping

Stored in services.env after provisioning:
```
IMMICH_UUID_dad="abc12345-6789-abcd-ef01-234567890abc"
IMMICH_UUID_mom="def45678-9012-abcd-ef34-567890123def"
IMMICH_UUID_son1="ghi78901-2345-abcd-ef56-789012345ghi"
IMMICH_UUID_son2="jkl01234-5678-abcd-ef78-901234567jkl"
```

Used by:
- task-ph4-06-configure-samba-uploads.sh (per-user Samba shares)
- Samba smb.conf (share path includes UUID or username)

## Samba Upload Shares

### Admin + Power Users: All-Uploads Share

The admin and power users get a consolidated `[all-uploads]` share pointing at the entire `library/` directory. This lets them browse all family members' uploads from one place in File Explorer. Standard users only see their own `[{username}-uploads]` share.

```
\\192.168.1.2\all-uploads\
├── admin/                    # Admin's own uploads
│   └── 2026/2026-02-28/     # Date-organized originals
├── def45678-.../             # Mom's uploads (UUID as folder name)
│   └── 2026/2026-03-15/
└── ghi78901-.../             # Kid's uploads (UUID as folder name)
    └── 2026/2026-03-20/
```

Curation workflow (admin / power user):
1. Open `\\192.168.1.2\all-uploads` in File Explorer
2. Browse through all users' date folders
3. Copy keepers to `\\192.168.1.2\Media\Photos\YYYY\MM\` (family archive)
4. Files inherit `media:media` ownership via Samba `force group = media`
5. Immich external library scan picks up new files in Media/Photos (daily at midnight)
6. Delete throwaway photos via Immich web UI (30-day trash retention)

### Per-User Upload Shares

Each user also gets their own `[{username}-uploads]` share pointing at their specific library subdirectory (read-only).

## External Library Configuration

1. Administration → External Libraries → Create Library
2. Owner: admin (or create per-user libraries for Folders view access)
3. Add import paths (container-internal paths, NOT host paths):
   - `/mnt/media/Photos` → maps to host /mnt/data/media/Photos (read-only)
   - `/mnt/family/Photos` → maps to host /mnt/data/family/Photos (read-only)
4. Scan schedule: `0 0 * * *` (daily at midnight, sufficient for home use)
   - Alternative every 6 hours if needed: `0 */6 * * *`
5. Trigger initial manual scan after adding paths
6. Verify existing photos appear in timeline

**Per-User External Libraries** (recommended for Folders view access):

External libraries are owned by the user who creates them. If only the admin creates external libraries, other users will NOT see those photos in their Folders view. To give all family members both timeline and Folders view access:

1. Create external libraries per user (each user gets their own library pointing to the same import paths)
2. Optionally enable partner sharing for cross-user timeline visibility of uploads
3. Each user must accept partner sharing from their own Account Settings

Automation: `scripts/operations/utils/immich/setup_user_libraries.sh` handles this for all users.

**Verify mounts**:
```bash
docker inspect immich-server --format \
  '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Mode}}){{println}}{{end}}'
```

## Photo Archive Prep E2E Workflow

For importing legacy photo archives from external HDD before Immich ingestion.

### Tool Dependencies

```bash
sudo apt install libimage-exiftool-perl   # exiftool (EXIF metadata reader/writer)
sudo apt install jdupes                    # duplicate file detection
```

### Script Locations

```
scripts/operations/utils/immich/
├── photo_audit.sh        # Orchestrator for archive inspection
├── metadata_report.sh    # EXIF completeness and camera source analysis
├── duplicate_scan.sh     # Duplicate detection via jdupes (estimate only)
├── year_distribution.sh  # Year distribution from EXIF capture dates
└── metadata_fix.sh       # EXIF metadata correction (future)
```

### Step-by-Step Workflow

#### 1. Mount HDD Read-Only

```bash
sudo mount -o ro /dev/sdX1 /mnt/external
ls /mnt/external/Photos/  # Verify contents visible
```

#### 2. Run Audit with Reports

```bash
sudo ./scripts/operations/utils/immich/photo_audit.sh /mnt/external/Photos --report
```

Output includes:
- Total file count and size
- Extension breakdown (case-insensitive)
- EXIF metadata completeness (DateTimeOriginal, CreateDate, camera Model)
- Camera/device source breakdown
- Duplicate file estimate (via jdupes)
- Year distribution from EXIF dates

#### 3. Review Metadata Report

- Check generated CSV for files missing DateTimeOriginal
- Note camera source breakdown and duplicate estimates
- Identify files with anomalous years (before 1990 or after current year)

#### 4. Fix Metadata (If Needed)

- Open metadata CSV in Excel
- Add FixDateTimeOriginal column (format as Text)
- Use format: `YYYY:MM:DD HH:MM:SS` (e.g., `2015:06:24 14:30:00`)
- Save as CSV UTF-8
- scp CSV back to server:
  ```bash
  scp fixes.csv admin@192.168.1.2:/tmp/
  ```

#### 5. Apply Metadata Fixes

```bash
# Preview changes first
sudo ./scripts/operations/utils/immich/metadata_fix.sh --dry-run /tmp/fixes.csv

# Apply changes
sudo ./scripts/operations/utils/immich/metadata_fix.sh /tmp/fixes.csv
```

#### 6. Re-Audit to Verify

```bash
sudo ./scripts/operations/utils/immich/photo_audit.sh /mnt/external/Photos --report
```

Confirm metadata completeness improved.

#### 7. Import to Immich

Copy files to external library directories:
```bash
# For curated media photos
rsync -av /mnt/external/Photos/ /mnt/data/media/Photos/

# For family photos
rsync -av /mnt/external/Photos/ /mnt/data/family/Photos/
```

External library scan will detect and index new files automatically (daily at midnight, or trigger manual scan from Immich admin UI).

### Immich Compatibility Check

**Supported extensions** (Immich will process these):

| Category | Extensions |
|----------|-----------|
| Photos | .jpg, .jpeg, .png, .gif, .heic, .heif, .webp, .tiff, .bmp |
| RAW | .raw, .cr2, .nef, .arw, .dng, .orf, .rw2, .raf, .srw |
| Video | .mp4, .mov, .avi, .mkv, .webm, .3gp, .m4v |

**Unsupported extensions** (Immich will ignore these):

| Extension | What It Is | Action |
|-----------|-----------|--------|
| .thm | Camera thumbnail file | Safe to ignore (Immich generates its own thumbnails) |
| .zip | Archive file | Extract contents, import supported files individually |
| .db | Database file (Thumbs.db, etc.) | Ignore (OS metadata, not photos) |
| .ini | Config file (desktop.ini, etc.) | Ignore (OS metadata) |
| .lrv | GoPro low-res video | Optional — import if you want low-res copies |
| .aae | iOS edit sidecar | Ignore (edit metadata, not a photo) |

## Related Documentation

- Deployment manual: docs/deployment_manuals/phase4-photo-management.md
- Storage structure: docs/05-storage.md
- Container restart/upgrade: docs/13-container-restart-procedure.md
- Architecture overview: docs/00-architecture-overview.md
