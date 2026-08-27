#!/usr/bin/env bash
set -euo pipefail

root=${1:?fixture root required}
work=${2:?work directory required}
base=$(cd "$(dirname "$0")" && pwd)/run-real-fpga-core.sh
patched="$work/run-real-fpga-core.patched.sh"

python3 - "$base" "$patched" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
old = '''text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
match = re.search(r'Timing estimate:\\s*([0-9.]+)\\s*ns\\s*\\(([0-9.]+)\\s*MHz\\)', text, re.I)
'''
new = '''text = "\\n".join(
    open(path, encoding='utf-8', errors='replace').read()
    for path in (sys.argv[1], sys.argv[2])
)
match = re.search(r'(?:Timing estimate|Total path delay):\\s*([0-9.]+)\\s*ns\\s*\\(([0-9.]+)\\s*MHz\\)', text, re.I)
'''
if old not in source:
    raise SystemExit('unable to patch IceTime parser in runner')
source = source.replace(old, new)
source = source.replace(
    "python3 - \"$work/icetime.txt\" <<'PY'",
    "python3 - \"$work/icetime.txt\" \"$work/icetime.stdout\" <<'PY'",
)
Path(sys.argv[2]).write_text(source, encoding='utf-8')
PY

exec bash "$patched" "$root" "$work"
