# Alice 版本号工具（供 release.sh 共用）
# 用法: VERSION_ROOT=/path/to/repo source scripts/lib/version.sh
#
# 同步位置:
#   - package.json                          version
#   - app.json                              expo.version + android.versionCode
#   - android/app/build.gradle              versionName + versionCode
#   - ios/Alice.xcodeproj/project.pbxproj   MARKETING_VERSION + CURRENT_PROJECT_VERSION

if [ -z "${VERSION_ROOT:-}" ]; then
  VERSION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

get_current_version() {
  node -e "
    const fs = require('fs');
    const path = require('path');
    const pkg = JSON.parse(fs.readFileSync(path.join(process.argv[1], 'package.json'), 'utf8'));
    process.stdout.write(pkg.version);
  " "$VERSION_ROOT"
}

get_current_version_code() {
  node -e "
    const fs = require('fs');
    const path = require('path');
    const app = JSON.parse(fs.readFileSync(path.join(process.argv[1], 'app.json'), 'utf8'));
    process.stdout.write(String(app.expo?.android?.versionCode ?? 0));
  " "$VERSION_ROOT"
}

resolve_version() {
  local arg="$1"
  node -e "
    const fs = require('fs');
    const path = require('path');

    const root = process.argv[1];
    const arg = process.argv[2];
    const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
    const current = pkg.version;

    const parse = (value) => {
      const normalized = value.replace(/^v/, '');
      if (!/^\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$/.test(normalized)) {
        throw new Error('无效的语义化版本: ' + value);
      }
      const [core, prerelease = ''] = normalized.split('-');
      const [major, minor, patch] = core.split('.').map(Number);
      return { major, minor, patch, prerelease, raw: normalized };
    };

    const format = ({ major, minor, patch, prerelease }) =>
      prerelease ? major + '.' + minor + '.' + patch + '-' + prerelease
                 : major + '.' + minor + '.' + patch;

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
      throw new Error('新版本 ' + next + ' 与当前版本相同');
    }

    process.stdout.write(next);
  " "$VERSION_ROOT" "$arg"
}

# Sync package.json, app.json, Android Gradle, and iOS Xcode project.
# Always bumps android versionCode / iOS CURRENT_PROJECT_VERSION by +1.
sync_versions() {
  local version="$1"
  node -e "
    const fs = require('fs');
    const path = require('path');

    const root = process.argv[1];
    const version = process.argv[2];

    const pkgPath = path.join(root, 'package.json');
    const appPath = path.join(root, 'app.json');
    const gradlePath = path.join(root, 'android/app/build.gradle');
    const pbxPath = path.join(root, 'ios/Alice.xcodeproj/project.pbxproj');

    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    pkg.version = version;
    fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');

    const app = JSON.parse(fs.readFileSync(appPath, 'utf8'));
    const prevCode = Number(app.expo?.android?.versionCode ?? 0);
    const versionCode = prevCode + 1;
    app.expo.version = version;
    app.expo.android = app.expo.android || {};
    app.expo.android.versionCode = versionCode;
    fs.writeFileSync(appPath, JSON.stringify(app, null, 2) + '\n');

    if (fs.existsSync(gradlePath)) {
      let gradle = fs.readFileSync(gradlePath, 'utf8');
      gradle = gradle.replace(/versionCode\\s+\\d+/, 'versionCode ' + versionCode);
      gradle = gradle.replace(/versionName\\s+\"[^\"]+\"/, 'versionName \"' + version + '\"');
      fs.writeFileSync(gradlePath, gradle);
    }

    if (fs.existsSync(pbxPath)) {
      let pbx = fs.readFileSync(pbxPath, 'utf8');
      pbx = pbx.replace(/MARKETING_VERSION = [^;]+;/g, 'MARKETING_VERSION = ' + version + ';');
      pbx = pbx.replace(
        /CURRENT_PROJECT_VERSION = \\d+;/g,
        'CURRENT_PROJECT_VERSION = ' + versionCode + ';'
      );
      fs.writeFileSync(pbxPath, pbx);
    }

    process.stdout.write(String(versionCode));
  " "$VERSION_ROOT" "$version"
}
