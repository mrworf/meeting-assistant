#!/usr/bin/env python3
"""Maintain public download links and the rolling, tested development build."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
from urllib.parse import quote

ASSET = "MeetingAssistant-macOS-universal.zip"
START = "<!-- downloads:start -->"
END = "<!-- downloads:end -->"


def api(path, method="GET", data=None):
    command = ["gh", "api", path, "--method", method]
    if data is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(data) if data is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def optional_release(repo):
    try:
        return api(f"repos/{repo}/releases/tags/development")
    except subprocess.CalledProcessError as error:
        if "404" in error.stderr:
            return None
        raise


def latest_official(releases):
    eligible = [release for release in releases
                if not release.get("draft") and release.get("published_at")
                and release["tag_name"].startswith("v")
                and any(asset["name"] == ASSET and asset.get("state", "uploaded") == "uploaded"
                        for asset in release.get("assets", []))]
    return max(eligible, key=lambda release: (release["published_at"], release["id"]), default=None)


def download_block(repo, release):
    base = f"https://github.com/{repo}/releases/download"
    development = f'{base}/development/{ASSET}'
    official = ('<img src="https://img.shields.io/badge/Official_version-unavailable-lightgrey?style=for-the-badge" alt="Official version unavailable">')
    if release:
        url = next(asset["browser_download_url"] for asset in release["assets"] if asset["name"] == ASSET)
        official = (f'<a href="{url}"><img src="https://img.shields.io/badge/Latest_official_version-download-blue?style=for-the-badge" '
                    'alt="Download latest official version"></a>')
    return (f'{START}\n<p align="center">\n'
            f'  <a href="{development}"><img src="https://img.shields.io/badge/Latest_build-download-orange?style=for-the-badge" alt="Download latest build"></a>\n'
            f'  {official}\n</p>\n{END}')


def update_readme(repo):
    pages = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{repo}/releases?per_page=100", "--paginate", "--slurp"], text=True))
    release = latest_official([release for page in pages for release in page])
    path = Path("README.md")
    content = path.read_text()
    if content.count(START) != 1 or content.count(END) != 1:
        raise ValueError("Expected exactly one marked README downloads block")
    before, remainder = content.split(START)
    _, after = remainder.split(END)
    updated = before + download_block(repo, release) + after
    if updated != content:
        path.write_text(updated)


def publish(repo):
    sha = os.environ["GITHUB_SHA"]
    run = os.environ["GITHUB_RUN_ID"]
    release = optional_release(repo)
    if release:
        ref = api(f"repos/{repo}/git/ref/tags/development")
        previous = ref["object"]["sha"]
        comparison = api(f"repos/{repo}/compare/{previous}...{sha}")
        if comparison["status"] == "behind":
            print("A newer development build is already published; skipping this run.")
            return
        if comparison["status"] not in ("ahead", "identical"):
            raise ValueError("Development build history diverged; refusing to replace it")
    # Upload the candidate before touching the previous public download.
    if not release:
        try:
            api(f"repos/{repo}/git/ref/tags/development")
        except subprocess.CalledProcessError as error:
            if "404" not in error.stderr:
                raise
            api(f"repos/{repo}/git/refs", "POST", {"ref": "refs/tags/development", "sha": sha})
        release = api(f"repos/{repo}/releases", "POST", {
            "tag_name": "development", "target_commitish": sha, "name": "Latest development build",
            "prerelease": True, "draft": True, "make_latest": "false"})
    temporary = f"candidate-{run}-{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}.zip"
    with tempfile.TemporaryDirectory() as directory:
        candidate = Path(directory) / temporary
        shutil.copyfile(ASSET, candidate)
        subprocess.run(["gh", "release", "upload", "development", str(candidate),
                        "--repo", repo, "--clobber"], check=True)
    assets = api(f"repos/{repo}/releases/{release['id']}/assets")
    uploaded = next(asset for asset in assets if asset["name"] == temporary)
    old = next((asset for asset in assets if asset["name"] == ASSET), None)
    if old:
        api(f"repos/{repo}/releases/assets/{old['id']}", "PATCH", {"name": f"previous-{run}.zip"})
    try:
        api(f"repos/{repo}/releases/assets/{uploaded['id']}", "PATCH", {"name": ASSET})
    except Exception:
        if old:
            api(f"repos/{repo}/releases/assets/{old['id']}", "PATCH", {"name": ASSET})
        raise
    api(f"repos/{repo}/git/refs/tags/development", "PATCH", {"sha": sha, "force": True})
    notes = (f"Latest successful main build: `{sha}`.\n\n"
             f"[Source commit](https://github.com/{repo}/commit/{sha}) · "
             f"[CI run](https://github.com/{repo}/actions/runs/{run})\n\n"
             "Development build for macOS 14+, Apple Silicon and Intel. "
             "Ad-hoc signed; not notarized. Replaced after successful main builds.")
    api(f"repos/{repo}/releases/{release['id']}", "PATCH", {
        "name": "Latest development build", "body": notes, "draft": False,
        "prerelease": True, "make_latest": "false"})
    if old:
        api(f"repos/{repo}/releases/assets/{old['id']}", "DELETE")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["publish", "readme"])
    args = parser.parse_args()
    repository = os.environ["GITHUB_REPOSITORY"]
    if args.action == "publish":
        publish(repository)
    else:
        update_readme(repository)
