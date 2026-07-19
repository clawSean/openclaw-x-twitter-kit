#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

printf '== bash syntax ==\n'
while IFS= read -r -d '' file; do
  bash -n "$file"
  printf 'ok %s\n' "$file"
done < <(find skills scripts -type f -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
  printf '\n== shellcheck ==\n'
  shell_files=()
  while IFS= read -r file; do
    shell_files+=("$file")
  done < <(find skills scripts -type f -name '*.sh' | sort)
  shellcheck "${shell_files[@]}"
else
  printf '\n== shellcheck skipped: not installed ==\n'
fi

printf '\n== skill frontmatter ==\n'
python3 - <<'PY'
from pathlib import Path
for path in Path('skills').glob('*/SKILL.md'):
    text = path.read_text()
    if not text.startswith('---\n'):
        raise SystemExit(f'{path}: missing frontmatter')
    front = text.split('---\n', 2)[1]
    if '\nname:' not in '\n' + front or '\ndescription:' not in '\n' + front:
        raise SystemExit(f'{path}: frontmatter needs name and description')
    print(f'ok {path}')
PY

printf '\n== single skill contract ==\n'
python3 - <<'PY'
import re
from pathlib import Path
skill = Path('skills/x-twitter-kit/SKILL.md').read_text()
readme = Path('README.md').read_text()
template = Path('skills/x-twitter-kit/templates/LOCAL_DEFAULTS.example.md')
checks = {
    'SKILL.md declares single-skill rule': re.search(r'^## Single[- ]Skill Rule$', skill, re.M),
    'SKILL.md references LOCAL_DEFAULTS.md': 'LOCAL_DEFAULTS.md' in skill,
    'README warns against separate host-specific skill': re.search(r'Do not keep a separate host-specific (Twitter|X/Twitter)[/-]?search skill active', readme),
    'LOCAL_DEFAULTS example exists': template.is_file(),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('\n'.join(f'FAIL {name}' for name in failed))
for name in checks:
    print(f'ok {name}')
PY

printf '\n== executable bits ==\n'
python3 - <<'PY'
import os
from pathlib import Path
for path in list(Path('skills').glob('*/scripts/*.sh')) + list(Path('scripts').glob('*.sh')):
    if not os.access(path, os.X_OK):
        raise SystemExit(f'{path} is not executable')
    print(f'ok {path}')
PY

printf '\n== secret pattern scan ==\n'
if grep -RInE \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude='ci-check.sh' \
  '(gh[pousr]_[A-Za-z0-9_]{20,}|xai-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|Authorization: Bearer [A-Za-z0-9._-]{20,}|code=[A-Za-z0-9_-]{20,}|client_secret[=:][A-Za-z0-9._-]{10,})' \
  .; then
  echo 'Potential secret-like content found. Redact or replace with placeholders.' >&2
  exit 1
fi
printf 'ok no obvious secrets\n'

printf '\n== offline capability tests ==\n'
scripts/test.sh

if [ "${XTK_RUN_ONLINE_TESTS:-0}" = "1" ]; then
  printf '\n== online capability tests ==\n'
  scripts/test-online.sh
else
  printf '\n== online capability tests skipped ==\n'
  printf 'Set XTK_RUN_ONLINE_TESTS=1 to run non-mutating live xAI/X checks.\n'
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '\n== whitespace check ==\n'
  git diff --check
fi
