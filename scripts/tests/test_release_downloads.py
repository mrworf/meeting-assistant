import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_downloads", Path(__file__).parents[1] / "release_downloads.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def release(tag, date, **extra):
    return dict(id=1, tag_name=tag, published_at=date, draft=False,
                assets=[dict(name=module.ASSET, browser_download_url="https://github.com/test/app.zip")], **extra)


class OfficialDownloadsTests(unittest.TestCase):
    def test_includes_alpha_and_ignores_development_and_drafts(self):
        stable = release("v1.0", "2026-01-01")
        alpha = release("v2-alpha", "2026-02-01", prerelease=True)
        development = release("development", "2026-03-01")
        draft = release("v3", "2026-04-01")
        draft["draft"] = True
        self.assertIs(module.latest_official([stable, draft, development, alpha]), alpha)

    def test_uses_publication_time_not_version_or_list_order(self):
        latest = release("v1.0.1", "2026-03-01")
        self.assertIs(module.latest_official([latest, release("v2.0", "2026-02-01")]), latest)

    def test_missing_or_unfinished_assets_are_excluded(self):
        missing = release("v3", "2026-04-01")
        missing["assets"] = []
        uploading = release("v4", "2026-05-01")
        uploading["assets"][0]["state"] = "new"
        self.assertIsNone(module.latest_official([missing, uploading]))

    def test_deleted_release_falls_back(self):
        old = release("v1", "2026-01-01")
        self.assertIs(module.latest_official([old]), old)
        self.assertIsNone(module.latest_official([]))

    def test_download_block(self):
        block = module.download_block("owner/repo", release("v1", "2026-01-01"))
        self.assertIn(f"/development/{module.ASSET}", block)
        self.assertIn("https://github.com/test/app.zip", block)
        self.assertIn("Official version unavailable", module.download_block("owner/repo", None))

    def test_readme_update_is_idempotent_and_preserves_surrounding_text(self):
        import os
        previous = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                Path("README.md").write_text(f"before\n{module.START}old{module.END}\nafter")
                with patch.object(module.subprocess, "check_output", return_value='[[]]'):
                    module.update_readme("owner/repo")
                    updated = Path("README.md").read_text()
                    module.update_readme("owner/repo")
                    self.assertEqual(updated, Path("README.md").read_text())
                    self.assertTrue(updated.startswith("before\n"))
                    self.assertTrue(updated.endswith("\nafter"))
            finally:
                os.chdir(previous)


class PublishTests(unittest.TestCase):
    @patch.dict("os.environ", GITHUB_SHA="new", GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1")
    def test_first_publication_creates_tag_and_prerelease(self):
        missing = subprocess.CalledProcessError(1, "gh", stderr="HTTP 404")
        assets = [{"id": 3, "name": "candidate-123-1.zip"}]
        with patch.object(module, "optional_release", return_value=None), patch.object(module, "api") as api, patch.object(module.shutil, "copyfile"), patch.object(module.subprocess, "run"):
            api.side_effect = [missing, {}, {"id": 1}, assets, {}, {}, {}]
            module.publish("owner/repo")
            self.assertEqual(api.call_args_list[1].args, ("repos/owner/repo/git/refs", "POST", {"ref": "refs/tags/development", "sha": "new"}))
            self.assertFalse(api.call_args.args[2]["draft"])
            self.assertTrue(api.call_args.args[2]["prerelease"])

    @patch.dict("os.environ", GITHUB_SHA="new", GITHUB_RUN_ID="123")
    def test_older_build_does_not_replace_newer_build(self):
        with patch.object(module, "optional_release", return_value={"id": 1}), patch.object(module, "api") as api:
            api.side_effect = [{"object": {"sha": "newer"}}, {"status": "behind"}]
            module.publish("owner/repo")
            self.assertTrue(all(call.args[1:] == () for call in api.call_args_list))

    @patch.dict("os.environ", GITHUB_SHA="new", GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1")
    def test_failed_upload_keeps_old_public_asset(self):
        with patch.object(module, "optional_release", return_value={"id": 1}), patch.object(module, "api") as api, patch.object(module.shutil, "copyfile"), patch.object(module.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "upload")):
            api.side_effect = [{"object": {"sha": "old"}}, {"status": "ahead"}]
            with self.assertRaises(subprocess.CalledProcessError):
                module.publish("owner/repo")
            self.assertEqual(api.call_count, 2)

    @patch.dict("os.environ", GITHUB_SHA="new", GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1")
    def test_failed_swap_restores_old_public_asset(self):
        assets = [{"id": 2, "name": module.ASSET}, {"id": 3, "name": "candidate-123-1.zip"}]
        with patch.object(module, "optional_release", return_value={"id": 1}), patch.object(module, "api") as api, patch.object(module.shutil, "copyfile"), patch.object(module.subprocess, "run"):
            api.side_effect = [{"object": {"sha": "old"}}, {"status": "ahead"}, assets, {}, RuntimeError("rename failed"), {}]
            with self.assertRaises(RuntimeError):
                module.publish("owner/repo")
            self.assertEqual(api.call_args.args, ("repos/owner/repo/releases/assets/2", "PATCH", {"name": module.ASSET}))


if __name__ == "__main__":
    unittest.main()
