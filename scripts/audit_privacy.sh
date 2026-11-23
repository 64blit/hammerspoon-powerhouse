#!/usr/bin/env bash
# ==============================================================================
# Hammerspoon Powerhouse — Privacy & Secret Safety Audit
#
# Scans tracked (or --staged) git files to ensure private keys, local paths,
# personal modules, or external symlinks are never accidentally committed/pushed.
#
# Usage:
#   ./scripts/audit_privacy.sh           # audit all tracked + staged files
#   ./scripts/audit_privacy.sh --staged  # audit staged files only (pre-commit hook)
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="all"
if [[ "${1:-}" == "--staged" ]]; then
    MODE="staged"
fi

python3 - "$MODE" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

mode = sys.argv[1]
repo = Path.cwd()

if mode == "staged":
    raw = subprocess.check_output(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        text=True,
    )
else:
    tracked = subprocess.check_output(["git", "ls-files"], text=True).splitlines()
    staged = subprocess.check_output(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        text=True,
    ).splitlines()
    raw = "\n".join(sorted(set(tracked + staged)))

files = [f for f in raw.splitlines() if f.strip()]
if not files:
    print("✅ Privacy audit passed (no files to scan).")
    sys.exit(0)

# Files/paths that must NEVER be committed
FORBIDDEN_FILE_PATTERNS = [
    re.compile(r"(^|/)\.env($|\.(?!example$))"),
    re.compile(r"(^|/)local_init\.lua$"),
    re.compile(r"\.local\.lua$"),
    re.compile(r"(^|/)\.privacy-denylist\.local$"),
    re.compile(r"^(private|local|\.local_backups)/"),
    re.compile(r"\.bak($|-)"),
    re.compile(r"\.(pem|key|p12|pfx)$"),
    re.compile(r"(^|/)__pycache__/"),
]

# Content checks on text files
SECRET_PATTERNS = [
    ("API key / token", re.compile(
        r"(sk-[a-zA-Z0-9_-]{20,}|sk-or-v1-[a-zA-Z0-9_-]{20,}|xai-[a-zA-Z0-9_-]{20,}|"
        r"AIza[0-9A-Za-z_-]{30,}|gsk_[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{20,}|"
        r"github_pat_[a-zA-Z0-9_]{20,}|xox[baprs]-[a-zA-Z0-9-]{15,}|"
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----)"
    )),
    ("Hardcoded /Users/<name> path", re.compile(r"/Users/[a-zA-Z0-9._-]+/")),
    ("Private Tailscale/LAN address", re.compile(
        r"\b(192\.168\.\d{1,3}\.\d{1,3}|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}|[a-z0-9-]+\.ts\.net)\b",
        re.I,
    )),
]

# Optional machine-local denylist (gitignored: .privacy-denylist.local), one regex per line
denylist_file = repo / ".privacy-denylist.local"
if denylist_file.is_file():
    for raw_line in denylist_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        pat_str = raw_line.strip()
        if pat_str and not pat_str.startswith("#"):
            SECRET_PATTERNS.append(("Local denylist match", re.compile(pat_str, re.I)))

SKIP_CONTENT_FILES = {
    "scripts/audit_privacy.sh",
    ".gitignore",
}

BINARY_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".mp3", ".wav", ".mp4", ".webm", ".icns", ".ico"}

errors: list[str] = []

for rel in files:
    p = repo / rel

    # 1. Forbidden file names
    for fpat in FORBIDDEN_FILE_PATTERNS:
        if fpat.search(rel):
            errors.append(f"[FORBIDDEN FILE] {rel} matches private/secret pattern {fpat.pattern}")

    if not p.exists() and not p.is_symlink():
        continue

    # 2. External symlinks
    if p.is_symlink():
        target = os.readlink(p)
        if os.path.isabs(target) or ".." in Path(target).parts:
            errors.append(f"[EXTERNAL SYMLINK] {rel} -> {target}")
        continue

    # 3. Unexpectedly large files (> 2MB outside Spoons/assets)
    size = p.stat().st_size
    if size > 2 * 1024 * 1024 and not rel.startswith(("Spoons/", "assets/")):
        errors.append(f"[LARGE FILE] {rel} ({size / (1024*1024):.1f} MB) — avoid committing binaries")

    # 4. Text content scan
    if rel in SKIP_CONTENT_FILES or p.suffix.lower() in BINARY_EXTS or rel.startswith("Spoons/"):
        continue

    try:
        data = p.read_bytes()
    except OSError:
        continue
    if b"\x00" in data[:4096]:
        continue  # binary file

    text = data.decode("utf-8", errors="ignore")
    for lineno, line in enumerate(text.splitlines(), 1):
        for label, pat in SECRET_PATTERNS:
            m = pat.search(line)
            if m:
                snippet = line.strip()[:100]
                errors.append(f"[{label}] {rel}:{lineno}: {snippet}")

if errors:
    print("❌ Privacy audit FAILED — potential private data or secrets detected:\n")
    for e in errors:
        print(f"  • {e}")
    print("\nFix these issues or move private items into ~/.hammerspoon/.env, local_init.lua, or private/.")
    sys.exit(1)

print(f"✅ Privacy audit passed ({len(files)} {mode} files scanned, 0 issues found).")
PY
