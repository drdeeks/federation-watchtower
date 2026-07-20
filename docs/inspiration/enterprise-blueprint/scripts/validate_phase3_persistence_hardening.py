#!/usr/bin/env python3
"""
Phase 3 Validator: Persistence & Hardening
Checks for backup, persistence, security hardening, firewall rules.
Run by ENFORCER only — not by agent.
"""

import sys
import os
from pathlib import Path


def check_persistence_hardening(project_root: Path) -> tuple[bool, list[str]]:
    """Validate Phase 3 persistence & hardening deliverables."""
    errors = []
    warnings = []
    
    # 1. Backup / persistence scripts
    backup_scripts = [
        "scripts/backup.sh", "scripts/restore.sh", "scripts/persist.sh",
        "scripts/snapshot.sh", "backup.sh", "restore.sh",
        "persistence/", "backup/"
    ]
    backup_found = any((project_root / p).exists() for p in backup_scripts)
    if not backup_found:
        errors.append("No backup/persistence scripts found (scripts/backup.sh, scripts/restore.sh, etc.)")
    
    # 2. Backup script is executable and has proper structure
    backup_sh = project_root / "scripts/backup.sh"
    if backup_sh.exists():
        if not os.access(backup_sh, os.X_OK):
            warnings.append("scripts/backup.sh is not executable (chmod +x)")
        content = backup_sh.read_text()
        if "pg_dump" not in content and "mysqldump" not in content and "sqlite3" not in content and "mongodump" not in content and "redis-cli" not in content:
            warnings.append("scripts/backup.sh may not contain actual DB backup commands")
    
    # 3. Firewall / security rules
    firewall_files = [
        "config/firewall.nft", "config/iptables.rules", "config/ufw.rules",
        "firewall.nft", "iptables.rules", "ufw.rules",
        "config/nftables.conf", "etc/nftables.conf",
        "scripts/firewall.sh", "scripts/security.sh"
    ]
    firewall_found = any((project_root / p).exists() for p in firewall_files)
    if not firewall_found:
        warnings.append("No firewall/security rules found (config/firewall.nft, iptables.rules, etc.)")
    
    # 4. Security hardening configs
    hardening = [
        "config/hardening.yaml", "config/security.yaml", "hardening.yaml",
        "security.yaml", "config/ssh.yaml", "ssh_config",
        "config/fail2ban/", "fail2ban/", "config/audit.yaml"
    ]
    if not any((project_root / p).exists() for p in hardening):
        warnings.append("No security hardening config found (config/hardening.yaml, fail2ban, etc.)")
    
    # 5. Data persistence / volume definitions
    persistence = [
        "docker-compose.yml", "docker-compose.yaml", "docker-compose.override.yml",
        "volumes/", "data/", "persistence/", "state/"
    ]
    # Check docker-compose for volumes
    docker_compose = project_root / "docker-compose.yml"
    if not docker_compose.exists():
        docker_compose = project_root / "docker-compose.yaml"
    
    volumes_defined = False
    if docker_compose.exists():
        try:
            content = docker_compose.read_text()
            if "volumes:" in content:
                volumes_defined = True
        except:
            pass
    
    if not volumes_defined and not any((project_root / p).exists() for p in persistence):
        warnings.append("No persistent volumes defined (docker-compose volumes, data/ directory, etc.)")
    
    # 6. Encryption / secrets management
    secrets = [
        "config/secrets.yaml", "config/vault.yaml", "secrets.yaml",
        ".sops.yaml", ".secrets.yaml", "age.key", "sops.yaml",
        "scripts/encrypt.sh", "scripts/decrypt.sh"
    ]
    if not any((project_root / p).exists() for p in secrets):
        warnings.append("No secrets management/encryption found (SOPS, age, vault, etc.)")
    
    # 7. SSL/TLS certificates config
    ssl = [
        "config/ssl/", "certs/", "ssl/", "letsencrypt/",
        "config/nginx/ssl/", "config/traefik/", "config/caddy/",
        "scripts/certbot.sh", "scripts/ssl.sh"
    ]
    if not any((project_root / p).exists() for p in ssl):
        warnings.append("No SSL/TLS certificate configuration found (config/ssl/, certbot, etc.)")
    
    # 8. Audit logging / compliance
    audit = [
        "config/audit.yaml", "audit.log", "scripts/audit.sh",
        "compliance/", "config/compliance.yaml", "config/auditd/"
    ]
    if not any((project_root / p).exists() for p in audit):
        warnings.append("No audit logging / compliance configuration found")
    
    return len(errors) == 0, errors + warnings


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase3_persistence_hardening.py <step-path>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase3_persistence_hardening.py <step-path>", file=sys.stderr)
        sys.exit(1)
    
    step_path = Path(sys.argv[1])
    project_root = step_path.parent.parent
    
    passed, messages = check_persistence_hardening(project_root)
    
    for msg in messages:
        level = "ERROR" if not passed else "WARN"
        print(f"[{level}] {msg}")
    
    if passed:
        print("[OK] Phase 3 Persistence & Hardening validation passed")
        sys.exit(0)
    else:
        print("[FAIL] Phase 3 Persistence & Hardening validation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()