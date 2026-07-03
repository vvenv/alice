# Monorepo 版本号工具（供 release.sh、bump-version.sh 共用）
# 用法: VERSION_ROOT=/path/to/repo source scripts/lib/version.sh

if [ -z "${VERSION_ROOT:-}" ]; then
  VERSION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

VERSION_PACKAGE_JSONS=(
  "$VERSION_ROOT/package.json"
  "$VERSION_ROOT/packages/server/package.json"
  "$VERSION_ROOT/packages/client/package.json"
  "$VERSION_ROOT/packages/shared/package.json"
)

get_current_version() {
  node --input-type=module -e "
    import fs from 'fs';
    import path from 'path';
    const pkg = JSON.parse(fs.readFileSync(path.join(process.argv[1], 'package.json'), 'utf8'));
    process.stdout.write(pkg.version);
  " "$VERSION_ROOT"
}

resolve_version() {
  local arg="$1"
  node --input-type=module -e "
    import fs from 'fs';
    import path from 'path';

    const root = process.argv[1];
    const arg = process.argv[2];
    const pkgPath = path.join(root, 'package.json');
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    const current = pkg.version;

    const parse = (value) => {
      const normalized = value.replace(/^v/, '');
      if (!/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/.test(normalized)) {
        throw new Error(\`无效的语义化版本: \${value}\`);
      }
      const [core, prerelease = ''] = normalized.split('-');
      const [major, minor, patch] = core.split('.').map(Number);
      return { major, minor, patch, prerelease, raw: normalized };
    };

    const format = ({ major, minor, patch, prerelease }) =>
      prerelease ? \`\${major}.\${minor}.\${patch}-\${prerelease}\` : \`\${major}.\${minor}.\${patch}\`;

    let next;
    if (arg === 'patch' || arg === 'minor' || arg === 'major') {
      const parsed = parse(current);
      if (parsed.prerelease) {
        throw new Error('当前为预发布版本，请显式指定目标版本号');
      }
      if (arg === 'patch') parsed.patch += 1;
      if (arg === 'minor') { parsed.minor += 1; parsed.patch = 0; }
      if (arg === 'major') { parsed.major += 1; parsed.minor = 0; parsed.patch = 0; }
      next = format(parsed);
    } else {
      next = parse(arg).raw;
    }

    if (next === current) {
      throw new Error(\`新版本 \${next} 与当前版本相同\`);
    }

    process.stdout.write(next);
  " "$VERSION_ROOT" "$arg"
}

compute_bump_previews() {
  node --input-type=module -e "
    import fs from 'fs';
    import path from 'path';

    const root = process.argv[1];
    const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
    const current = pkg.version;
    const [core, prerelease = ''] = current.split('-');
    if (prerelease) process.exit(2);
    const [major, minor, patch] = core.split('.').map(Number);
    console.log(\`\${major}.\${minor}.\${patch + 1}\`);
    console.log(\`\${major}.\${minor + 1}.0\`);
    console.log(\`\${major + 1}.0.0\`);
  " "$VERSION_ROOT" 2>/dev/null || true
}

sync_package_versions() {
  local version="$1"
  local pkg
  for pkg in "${VERSION_PACKAGE_JSONS[@]}"; do
    node --input-type=module -e "
      import fs from 'fs';
      const file = process.argv[1];
      const ver = process.argv[2];
      const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
      pkg.version = ver;
      fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + '\n');
    " "$pkg" "$version"
  done
}

version_tag_exists() {
  local version="$1"
  git -C "$VERSION_ROOT" rev-parse "v${version}" >/dev/null 2>&1
}
