"""Exercise release guards with local fixtures and a fake gh; never publish."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ReleasePipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.scripts = self.root / "app/scripts"
        self.scripts.mkdir(parents=True)
        original = Path(__file__).resolve().parents[1] / "scripts"
        for name in ("publish-release.sh", "package-release.sh"):
            shutil.copy2(original / name, self.scripts / name)
        self.assets = self.root / "dist/releases"
        self.assets.mkdir(parents=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "gh-calls.jsonl"
        gh = self.bin / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["TEST_GH_CALLS"], "a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1] == "api":
    print("main" if sys.argv[-1] == ".default_branch" else os.environ["GITHUB_SHA"])
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        GH_REPO="test/local-fixture", GITHUB_SHA="a" * 40,
                        GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1", GITHUB_REF_NAME="main",
                        CI_BUILD_ID="1.1", TEST_GH_CALLS=str(self.calls), GITHUB_STEP_SUMMARY="")

    def package(self, arch="arm64", **overrides):
        path = self.assets / f"InputMethodPrompt-test-{arch}.json"
        metadata = dict(commit=self.env["GITHUB_SHA"], ci_build="1.1", architecture=arch,
                        version="1.11.1", app_build="30")
        metadata.update(overrides)
        path.write_text(json.dumps(metadata))
        path.with_suffix(".zip").write_bytes(b"local test fixture, not a real application")
        path.with_suffix(".sha256").write_text("".join(
            hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n"
            for p in (path.with_suffix(".zip"), path)))
        return path

    def publish(self, success):
        result = subprocess.run(["bash", str(self.scripts / "publish-release.sh")],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        if not success:
            self.assertFalse(self.calls.exists(), "Invalid packages must fail before invoking gh")

    def test_arm64_alone_publishes_three_assets(self):
        path = self.package()
        self.publish(True)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        creation = next(call for call in calls if call[:2] == ["release", "create"])
        attached = {argument for argument in creation if argument.endswith((".zip", ".json", ".sha256"))}
        self.assertEqual(attached, {"./" + path.with_suffix(suffix).name for suffix in (".zip", ".json", ".sha256")})
        self.assertEqual(calls[-1], ["release", "edit", "ci-123-1", "--draft=false", "--latest=true"])
        self.assertIn("M 系列芯片", (self.assets / "release-notes.md").read_text())

    def test_intel_metadata_is_rejected(self):
        self.package("x86_64")
        self.publish(False)

    def test_mixed_architectures_are_rejected(self):
        self.package()
        self.package("x86_64")
        self.publish(False)

    def test_stale_extra_archive_is_rejected(self):
        self.package()
        (self.assets / "stale-x86_64.zip").write_bytes(b"old artifact")
        self.publish(False)

    def test_wrong_commit_is_rejected(self):
        self.package(commit="b" * 40)
        self.publish(False)

    def test_wrong_batch_is_rejected(self):
        self.package(ci_build="0.1")
        self.publish(False)

    def test_corrupt_archive_is_rejected(self):
        path = self.package()
        path.with_suffix(".zip").write_bytes(b"corrupt")
        self.publish(False)

    def test_missing_metadata_checksum_is_rejected(self):
        path = self.package()
        checksum = path.with_suffix(".sha256")
        checksum.write_text(checksum.read_text().splitlines()[0] + "\n")
        self.publish(False)

    def test_packaging_on_intel_stops_before_building(self):
        uname = self.bin / "uname"
        uname.write_text("#!/bin/sh\nprintf 'x86_64\\n'\n")
        uname.chmod(0o755)
        result = subprocess.run(["bash", str(self.scripts / "package-release.sh")],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("仅支持 Apple Silicon（arm64）打包", result.stderr)
        self.assertFalse((self.root / "app/.build").exists())


if __name__ == "__main__":
    unittest.main()
