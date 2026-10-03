"""Package only public project files; never include local signing or build output."""
from pathlib import Path
import re
import zipfile

root = Path(__file__).resolve().parent.parent
files = [root / p for p in ['.gitignore', 'README.md', 'README.zh-CN.md', 'LICENSE', 'NOTICE', 'CONTRIBUTING.md']]
for directory in ['Shared', 'iPhone', 'Mac', 'Config', 'scripts', 'docs', 'Touchpad.xcodeproj']:
    for path in (root / directory).rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        if path.name in {'.DS_Store', 'Local.xcconfig', 'BuildStatus.md'}:
            continue
        if any(part in {'xcuserdata', '__pycache__'} for part in path.parts):
            continue
        if path.suffix in {'.xcuserstate', '.pyc', '.html', '.css', '.js'}:
            continue
        files.append(path)

for path in files:
    if path.suffix.lower() in {'.png', '.jpg', '.jpeg', '.zip'}:
        continue
    text = path.read_text(encoding='utf-8')
    patterns = [r'/Users/[A-Za-z][^/\s]*/', r'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}',
                r'touchpad://pair\?[^\s"<>]+', r'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----']
    for pattern in patterns:
        if re.search(pattern, text):
            raise SystemExit(f'Private configuration or credentials found in {path.relative_to(root)}')

output = root / 'dist/Pocket-Touchpad-GitHub.zip'
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(set(files)):
        archive.write(path, 'Pocket-Touchpad/' + path.relative_to(root).as_posix())
print(f'{len(set(files))} files → {output.name} ({output.stat().st_size / 1024 / 1024:.1f} MB)')
