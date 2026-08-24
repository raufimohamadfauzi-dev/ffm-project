from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
missing = []
for dart_file in root.rglob('*.dart'):
    text = dart_file.read_text(errors='ignore')
    for match in re.finditer(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", text):
        target = match.group(1)
        if target.startswith('.'):
            resolved = (dart_file.parent / target).resolve()
            if not resolved.is_file():
                missing.append((dart_file.relative_to(root), target))
if missing:
    for source, target in missing:
        print(f'MISSING {source}: {target}')
    raise SystemExit(1)
print('OK: seluruh import/export/part relatif menunjuk ke file yang ada')
