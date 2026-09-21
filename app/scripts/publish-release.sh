#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
cd "$WORKSPACE_DIR/dist/releases"
: "${GH_REPO:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_REF_NAME:?}" "${CI_BUILD_ID:?}"
case "$GITHUB_REF_NAME" in main|master) ;; *) printf '仅允许主分支发布\n' >&2; exit 1 ;; esac
# Require both architectures from this exact workflow attempt before publishing anything.
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
metadata = sorted(Path('.').glob('*.json'))
assert len(metadata) == 2, '需要两个架构的构建元数据'
architectures = set()
versions = set()
for path in metadata:
    data = json.loads(path.read_text())
    assert data['commit'] == os.environ['GITHUB_SHA'], '构建提交不一致'
    assert data['ci_build'] == os.environ['CI_BUILD_ID'], '构建批次不一致'
    architectures.add(data['architecture'])
    versions.add((data['version'], data['app_build']))
    for suffix in ('.zip', '.sha256'):
        assert path.with_suffix(suffix).is_file(), f'缺少 {suffix} 文件'
    for line in path.with_suffix('.sha256').read_text().splitlines():
        expected, name = line.split('  ', 1)
        assert Path(name).name == name, '校验文件含目录路径'
        assert hashlib.sha256(Path(name).read_bytes()).hexdigest() == expected, 'SHA-256 不一致'
assert architectures == {'arm64', 'x86_64'}, '构建架构不完整'
assert len(versions) == 1, '两个架构的版本不一致'
version, build = versions.pop()
Path('release-title.txt').write_text(f'中英提示 v{version} · build {build} · CI {os.environ["CI_BUILD_ID"]}')
Path('release-notes.md').write_text(f'''由 {os.environ['GITHUB_REF_NAME']} 分支自动构建。

- 应用版本：{version}（构建 {build}）
- 源码提交：{os.environ['GITHUB_SHA']}
- CI 批次：{os.environ['CI_BUILD_ID']}
- 构建记录：https://github.com/{os.environ['GH_REPO']}/actions/runs/{os.environ['GITHUB_RUN_ID']}

下载 Assets 中以 arm64.zip 结尾的文件用于 Apple Silicon（M 系列），以 x86_64.zip 结尾的文件用于 Intel。解压后将「中英提示.app」放入「应用程序」。最低 macOS 13。

这是持续构建版本，已完成自动回归、构建、签名和压缩包校验，不代表所有系统版本和设备均已人工验收。使用临时签名，未做 Apple 公证；首次启动若被系统阻止，在确认下载来源后通过「系统设置 → 隐私与安全性 → 仍要打开」允许。无需关闭 Gatekeeper。

同名 .json 记录构建信息，.sha256 用于校验下载内容。详细功能、设置与使用方式见仓库 README。
''')
PY
TAG="ci-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
# A unique draft prevents incomplete asset uploads from becoming a public release.
gh release create "$TAG" ./*.zip ./*.json ./*.sha256 \
    --target "$GITHUB_SHA" --title "$(cat release-title.txt)" \
    --notes-file release-notes.md --draft
# An older build finishing late must not replace the newest default-branch download.
DEFAULT_BRANCH="$(gh api "repos/$GH_REPO" --jq .default_branch)"
LATEST_SHA="$(gh api "repos/$GH_REPO/commits/$DEFAULT_BRANCH" --jq .sha)"
MAKE_LATEST=false
if [[ "$GITHUB_REF_NAME" == "$DEFAULT_BRANCH" && "$GITHUB_SHA" == "$LATEST_SHA" ]]; then
    MAKE_LATEST=true
fi
gh release edit "$TAG" --draft=false --latest="$MAKE_LATEST"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '### 下载已发布\n\n[下载本次构建](https://github.com/%s/releases/tag/%s)\n' "$GH_REPO" "$TAG" >> "$GITHUB_STEP_SUMMARY"
fi
