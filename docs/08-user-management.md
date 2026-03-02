# User Management - Operational Reference

## Overview

User provisioning system provides automated user creation, updates, and deletion with consistent folder structures, permissions, and Samba share configuration. The system supports three user roles (Admin, Power User, Standard User) with role-based permissions for SSH access, sudo privileges, and Docker access.

## User Roles

### Admin User

**Capabilities**:
- Full system access (sudo privileges)
- Docker container management
- SSH access from all devices
- Read/write access to all shares (Personal, Family, Media)
- Media library management (via media group)

**Linux Groups**: family, sudo, docker, media

**Use Cases**:
- System administration and maintenance
- Service deployment and configuration
- User provisioning and management
- Media library curation

### Power User

**Capabilities**:
- Limited system access (no sudo)
- Docker container management
- SSH access from personal device only
- Read/write access to Personal and Family shares
- Media library management (via media group)

**Linux Groups**: family, docker, media

**Use Cases**:
- Media library curation
- Container management (personal services)
- File management via SSH
- Development and testing

### Standard User

**Capabilities**:
- No system access (no sudo, no SSH)
- Web apps and Samba only
- Read/write access to Personal and Family shares
- Read-only access to Media share

**Linux Groups**: family

**Use Cases**:
- File access via Samba
- Media consumption via Jellyfin
- Family collaboration via shared folders
- Non-technical family members

## Role Comparison

| Capability | Admin | Power User | Standard User |
|------------|-------|------------|---------------|
| Personal Folder | RW | RW | RW |
| Family Share | RW | RW | RW |
| Media Share | RW | RW | RO |
| SSH Access | Yes (all devices) | Yes (personal device) | No |
| sudo Access | Yes | No | No |
| docker Access | Yes | Yes | No |
| Media Group | Yes | Yes | No |
| Jellyfin Access | Yes (Admin) | Yes (User) | Yes (User) |

## Provisioning Workflow

### Create User

**Purpose**: Create new user with Linux account, Samba account, personal folders, and Samba share.

**Prerequisites**:
- Samba container running
- secrets.env loaded with SAMBA_PASSWORD_{username} variable
- SSH public key prepared (for Admin/Power users)

**Command**:
```bash
cd /opt/homeserver/scripts/operations/user-management
sudo ./create-user.sh <username> <role> [ssh-public-key]
```

**Parameters**:
- `username`: Lowercase alphanumeric with underscores (e.g., admin_user)
- `role`: admin, power, or standard
- `ssh-public-key`: Optional SSH public key file path (for admin/power roles only)

**Example**:
```bash
# Create admin user with SSH key
sudo ./create-user.sh admin_user admin ~/.ssh/admin_user.pub

# Create power user with SSH key
sudo ./create-user.sh power_user power ~/.ssh/power_user.pub

# Create standard user (no SSH key)
sudo ./create-user.sh standard_user standard
```

**Operations Performed**:
1. Create Linux user with random password (expired)
2. Add user to appropriate groups (family, sudo, docker, media)
3. Create Samba user with password from secrets.env
4. Create personal folder structure (Documents, Photos, Videos, Music)
5. Set ownership and permissions (770 for personal folders)
6. Create Samba share for personal folder
7. Configure SSH access (if key provided and role allows)
8. Reload Samba configuration
9. Log all operations to /var/log/user-provisioning.log

**Output**:
```
User created successfully:
  Username: admin_user
  Role: admin
  Groups: admin_user family sudo docker media
  Home Directory: /home/admin_user
  Personal Folder: /mnt/data/users/admin_user
  Samba Share: \\192.168.1.2\admin_user
  SSH Access: Enabled
```

**Important Notes**:
- Samba passwords MUST be stored in secrets.env as SAMBA_PASSWORD_{username}
- Users must log out and back in for media group membership to take effect
- Personal folders use 770 permissions (user:family) to allow Samba container access
- GECOS field set to username for Samba display name

### Update User

**Purpose**: Update existing user's role, SSH key, or Samba password.

**Command**:
```bash
cd /opt/homeserver/scripts/operations/user-management
sudo ./update-user.sh <username> <update-type> [value]
```

**Update Types**:

**1. Role Update**:
```bash
sudo ./update-user.sh admin_user role power
```

Operations:
- Remove from sudo group (if downgrading from admin)
- Add to docker group (if upgrading to power/admin)
- Remove from docker group (if downgrading to standard)
- Remove SSH access (if downgrading to standard)
- Log the change

**2. SSH Key Update**:
```bash
sudo ./update-user.sh admin_user ssh-key /path/to/new-key.pub
```

Operations:
- Backup existing authorized_keys
- Replace with new key
- Validate key format
- Restore backup if validation fails
- Log the change

**3. Samba Password Update**:
```bash
sudo ./update-user.sh admin_user samba-password
```

Operations:
- Prompt for new password
- Validate password length (min 8 characters)
- Update with smbpasswd
- Log the change

### Delete User

**Purpose**: Delete user and optionally archive personal data.

**Command**:
```bash
cd /opt/homeserver/scripts/operations/user-management
sudo ./delete-user.sh <username> [--keep-data]
```

**Parameters**:
- `username`: Existing username
- `--keep-data`: Optional flag to archive personal data instead of deleting

**Example**:
```bash
# Delete user and personal data
sudo ./delete-user.sh standard_user

# Delete user but archive personal data
sudo ./delete-user.sh standard_user --keep-data
```

**Operations Performed**:
1. Prompt for confirmation
2. Remove Linux user and home directory
3. Remove Samba user
4. Remove personal share from smb.conf
5. Reload Samba configuration
6. Delete or archive personal folder

**Data Handling**:
- **Without --keep-data**: Personal folder deleted permanently
- **With --keep-data**: Personal folder renamed to {username}.deleted.{timestamp}, ownership changed to root:root, permissions set to 700

**Output**:
```
User deleted successfully:
  Username: standard_user
  Personal data: Archived to /mnt/data/users/standard_user.deleted.20250220_103045
```

### List Users

**Purpose**: List all provisioned users with details.

**Command**:
```bash
cd /opt/homeserver/scripts/operations/user-management
sudo ./list-users.sh [--json]
```

**Parameters**:
- `--json`: Optional flag to output JSON format

**Output (Table)**:
```
USERNAME      ROLE      GROUPS              HOME DIR           PERSONAL FOLDER                SAMBA SHARE              SSH ACCESS  LAST LOGIN
admin_user    admin     family,sudo,docker  /home/admin_user   /mnt/data/users/admin_user     \\192.168.1.2\admin_user  Enabled     2025-02-20 10:30
power_user    power     family,docker       /home/power_user   /mnt/data/users/power_user     \\192.168.1.2\power_user  Enabled     2025-02-19 15:45
standard_user standard  family              /home/standard_user /mnt/data/users/standard_user \\192.168.1.2\standard_user Disabled   2025-02-18 09:15
```

**Output (JSON)**:
```json
[
  {
    "username": "admin_user",
    "role": "admin",
    "groups": ["family", "sudo", "docker", "media"],
    "home_dir": "/home/admin_user",
    "personal_folder": "/mnt/data/users/admin_user",
    "samba_share": "\\\\192.168.1.2\\admin_user",
    "ssh_access": true,
    "last_login": "2025-02-20 10:30"
  }
]
```

## Script Usage

### Prerequisites

**Before running any provisioning script**:
1. SSH to server: `ssh user@192.168.1.2`
2. Navigate to scripts directory: `cd /opt/homeserver/scripts/operations/user-management`
3. Load secrets.env: `source /opt/homeserver/configs/secrets.env`
4. Verify Samba container running: `docker ps | grep samba`

### Secrets Management

**secrets.env Format**:
```bash
# Samba passwords (one per user)
SAMBA_PASSWORD_admin_user="SecurePassword123"
SAMBA_PASSWORD_power_user="AnotherSecurePass456"
SAMBA_PASSWORD_standard_user="StandardUserPass789"
```

**Security Requirements**:
- File location: /opt/homeserver/configs/secrets.env
- File permissions: 600 (root-only)
- Never commit to Git
- Minimum password length: 8 characters
- Store in password manager for backup

**Loading Secrets**:
```bash
# Load secrets before running provisioning scripts
source /opt/homeserver/configs/secrets.env

# Verify variable loaded
echo $SAMBA_PASSWORD_admin_user
```

### SSH Key Preparation

**Generate SSH Key** (Ed25519 with passphrase):
```bash
# On client machine
ssh-keygen -t ed25519 -C "admin_user@homeserver" -f ~/.ssh/admin_user

# Enter passphrase when prompted (required)
```

**Copy Public Key to Server**:
```bash
# Copy public key file to server
scp ~/.ssh/admin_user.pub user@192.168.1.2:/tmp/

# Or copy public key content to clipboard and paste when needed
cat ~/.ssh/admin_user.pub
```

### Common Workflows

**Provision New Admin User**:
```bash
# 1. Add Samba password to secrets.env
echo 'SAMBA_PASSWORD_admin_user="SecurePassword123"' | sudo tee -a /opt/homeserver/configs/secrets.env

# 2. Load secrets
source /opt/homeserver/configs/secrets.env

# 3. Copy SSH public key to server
scp ~/.ssh/admin_user.pub user@192.168.1.2:/tmp/

# 4. SSH to server and run provisioning script
ssh user@192.168.1.2
cd /opt/homeserver/scripts/operations/user-management
sudo ./create-user.sh admin_user admin /tmp/admin_user.pub

# 5. Verify user created
sudo ./list-users.sh
```

**Provision New Power User**:
```bash
# Same as admin user, but with role "power"
sudo ./create-user.sh power_user power /tmp/power_user.pub
```

**Provision New Standard User**:
```bash
# 1. Add Samba password to secrets.env
echo 'SAMBA_PASSWORD_standard_user="StandardUserPass789"' | sudo tee -a /opt/homeserver/configs/secrets.env

# 2. Load secrets
source /opt/homeserver/configs/secrets.env

# 3. Run provisioning script (no SSH key)
cd /opt/homeserver/scripts/operations/user-management
sudo ./create-user.sh standard_user standard

# 4. Verify user created
sudo ./list-users.sh
```

**Change User Role**:
```bash
# Downgrade admin to power user
sudo ./update-user.sh admin_user role power

# Upgrade power user to admin
sudo ./update-user.sh power_user role admin

# Downgrade power user to standard (removes SSH access)
sudo ./update-user.sh power_user role standard
```

**Rotate SSH Key**:
```bash
# 1. Generate new SSH key on client
ssh-keygen -t ed25519 -C "admin_user@homeserver" -f ~/.ssh/admin_user_new

# 2. Copy new public key to server
scp ~/.ssh/admin_user_new.pub user@192.168.1.2:/tmp/

# 3. Update SSH key on server
ssh user@192.168.1.2
cd /opt/homeserver/scripts/operations/user-management
sudo ./update-user.sh admin_user ssh-key /tmp/admin_user_new.pub

# 4. Test new key
ssh -i ~/.ssh/admin_user_new admin_user@192.168.1.2
```

**Reset Samba Password**:
```bash
# Interactive password prompt
sudo ./update-user.sh admin_user samba-password

# Or use Docker exec for direct password reset
docker exec -it samba smbpasswd admin_user
```

## Troubleshooting

### User Creation Fails

**Error: "Samba password not found in environment"**

Cause: SAMBA_PASSWORD_{username} variable not set in secrets.env

Solution:
```bash
# Add password to secrets.env
echo 'SAMBA_PASSWORD_username="SecurePassword123"' | sudo tee -a /opt/homeserver/configs/secrets.env

# Load secrets
source /opt/homeserver/configs/secrets.env

# Retry user creation
sudo ./create-user.sh username role
```

**Error: "User already exists"**

Cause: Username already exists in system

Solution:
```bash
# Check if user exists
id username

# Delete existing user first
sudo ./delete-user.sh username --keep-data

# Or use update-user.sh to modify existing user
sudo ./update-user.sh username role new_role
```

**Error: "Samba configuration reload failed"**

Cause: Samba container not running or smb.conf syntax error

Solution:
```bash
# Check Samba container status
docker ps | grep samba

# Check Samba logs
docker logs samba --tail 50

# Validate smb.conf syntax
docker exec samba testparm -s

# Restart Samba container
docker restart samba
```

### SSH Access Not Working

**Cannot connect via SSH**

Cause: SSH key not configured correctly or permissions incorrect

Solution:
```bash
# Verify SSH key exists
sudo ls -la /home/username/.ssh/authorized_keys

# Verify SSH key permissions
sudo ls -la /home/username/.ssh/
# Expected: drwx------ (700) for .ssh directory
# Expected: -rw------- (600) for authorized_keys file

# Fix permissions if incorrect
sudo chmod 700 /home/username/.ssh
sudo chmod 600 /home/username/.ssh/authorized_keys
sudo chown -R username:username /home/username/.ssh

# Test SSH connection with verbose output
ssh -v username@192.168.1.2
```

**SSH key rejected**

Cause: SSH key format invalid or wrong key used

Solution:
```bash
# Verify SSH key format on client
cat ~/.ssh/username.pub
# Should start with: ssh-ed25519 AAAA...

# Verify SSH key on server matches client
sudo cat /home/username/.ssh/authorized_keys

# Update SSH key if mismatch
sudo ./update-user.sh username ssh-key /path/to/correct-key.pub
```

### Samba Authentication Fails

**Cannot authenticate to Samba share**

Cause: Samba user not created or password incorrect

Solution:
```bash
# Verify Samba user exists
docker exec samba pdbedit -L | grep username

# Reset Samba password
docker exec -it samba smbpasswd username

# Or use update-user.sh
sudo ./update-user.sh username samba-password
```

**Samba user has corrupted UID**

Cause: Missing /etc/passwd or /etc/group mounts in Samba container

Solution:
```bash
# Verify container can see host users
docker exec samba getent passwd username
docker exec samba getent group family

# If users not visible, check docker-compose.yml mounts
grep -A 5 "volumes:" /opt/homeserver/configs/docker-compose/samba.yml
# Should include:
#   - /etc/passwd:/etc/passwd:ro
#   - /etc/group:/etc/group:ro

# Recreate container with correct mounts
cd /opt/homeserver/configs/docker-compose
docker compose -f samba.yml down
docker compose -f samba.yml up -d

# Re-provision user
sudo ./create-user.sh username role
```

### Permission Denied on Shares

**Cannot access personal share**

Cause: Incorrect folder permissions or Samba container PGID mismatch

Solution:
```bash
# Check folder ownership and permissions
ls -la /mnt/data/users/username/
# Expected: drwxrwx--- username family

# Fix permissions
sudo chown -R username:family /mnt/data/users/username/
sudo chmod 770 /mnt/data/users/username/
sudo chmod 770 /mnt/data/users/username/*

# Verify Samba container runs with family group
docker exec samba id
# Expected output should include: groups=1001(family)

# Check family group GID
getent group family
# Expected: family:x:1001:...

# Verify PGID in docker-compose.yml matches family GID
grep PGID /opt/homeserver/configs/docker-compose/samba.yml
```

**Cannot write to Media share**

Cause: User not in media group

Solution:
```bash
# Check user groups
groups username
# Expected for admin/power: username family docker media

# Add user to media group
sudo usermod -aG media username

# User must log out and back in for group membership to take effect
# Verify group membership after re-login
groups username
```

### Media Group Membership Not Working

**User added to media group but still cannot write to Media share**

Cause: User has not logged out and back in

Solution:
```bash
# Group membership changes require re-login
# 1. User logs out of all sessions
# 2. User logs back in
# 3. Verify group membership
groups username
# Should show: username family docker media

# Alternative: Use newgrp to activate group in current session
newgrp media
```

## File Locations

- **Provisioning scripts**: /opt/homeserver/scripts/operations/user-management/
- **Secrets file**: /opt/homeserver/configs/secrets.env
- **Provisioning log**: /var/log/user-provisioning.log
- **Personal folders**: /mnt/data/users/{username}/
- **Samba config**: /opt/homeserver/configs/samba/smb.conf
- **Samba user database**: /mnt/data/services/samba/lib/private/passdb.tdb

## Related Documentation

- Architecture Overview: docs/00-architecture-overview.md
- Foundation Layer: docs/01-foundation-layer.md
- Infrastructure Layer: docs/02-infrastructure-layer.md
- Samba File Sharing: docs/06-samba-file-sharing.md
- Storage Configuration: docs/05-storage.md
- Deployment Manual: docs/deployment_manuals/phase3-core-services.md

## Lessons Learned

### Samba Password Automation

**Problem**: Initial design required interactive password entry during user provisioning, preventing automated deployment.

**Solution**: Store Samba passwords in secrets.env as SAMBA_PASSWORD_{username} variables, load before running scripts.

**Benefits**: Enables automated, non-interactive user provisioning via deployment scripts.

### Personal Folder Permissions

**Problem**: Original design used 700 permissions (user-only), preventing Samba container from accessing folders.

**Solution**: Changed to 770 permissions (user:family) and set PGID=family in container, allowing both user and Samba to access.

**Trade-off**: Family group members can technically access personal folders at filesystem level, but Samba share permissions restrict access to owner only.

### Media Group Membership

**Problem**: Users added to media group could not immediately write to Media share.

**Solution**: Users must log out and back in for group membership to take effect. Document this requirement clearly.

**Verification**: Always verify group membership after re-login: `groups username`

### GECOS Field for Samba Display Names

**Problem**: Samba users created without GECOS field showed incorrect or empty display names in `pdbedit -L`.

**Solution**: Set GECOS field to username during user creation: `useradd -c "${username}" ...`

**Why Required**: Samba uses GECOS field (5th field in /etc/passwd) as display name. Without it, Samba may show corrupted or empty names.
