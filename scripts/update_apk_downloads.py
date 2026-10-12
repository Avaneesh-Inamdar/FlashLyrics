"""Publish a Shields endpoint containing only public release APK downloads."""
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

REPOSITORY = os.environ.get("GITHUB_REPOSITORY", "Avaneesh-Inamdar/FlashLyrics")


def apk_downloads(releases):
    return sum(
        asset["download_count"]
        for release in releases
        if not release.get("draft", False)
        for asset in release.get("assets", [])
        if asset["name"].lower().endswith(".apk")
    )


def main():
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "FlashLyrics-download-counter"}
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    total = 0
    page = 1
    while True:
        url = f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=100&page={page}"
        with urlopen(Request(url, headers=headers), timeout=30) as response:
            releases = json.load(response)
        total += apk_downloads(releases)
        if len(releases) < 100:
            break
        page += 1
    badge = {"schemaVersion": 1, "label": "APK downloads", "message": f"{total:,}", "color": "21815B"}
    destination = Path(__file__).resolve().parents[1] / "docs" / "apk-downloads.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(badge, indent=2) + "\n", encoding="utf-8")
    print(f"Public GitHub Release APK downloads: {total:,}")


if __name__ == "__main__":
    main()
