#!/usr/bin/env python3
"""Reuse only APKs built from identical tracked app inputs and the fixed QA recipe.

The optional cache lookup is bounded to five recent artifacts. A cache miss or
unavailable API always falls back to a fresh build; capture verification is strict.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
import zipfile


ARTIFACT = "quran-android-foldable-build"
WORKFLOW = ".github/workflows/samsung-foldable-visual-check.yml"
MAX_CANDIDATES = 5
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
TOOLCHAIN = {
    "runner": "ubuntu-24.04",
    "flutter": "3.38.1",
    "flutter_channel": "stable",
    "java": "17",
    "java_distribution": "temurin",
    "android_command_line_tools": "16111833",
    "build_mode": "debug",
}
BUILD_COMMAND = (
    "flutter build apk --debug --no-pub --target-platform android-x64 "
    "--dart-define=READER_LAYOUT_QA=true"
)
APP_PATHSPEC = [".", ":(top,exclude).github"]
ROOT = Path(__file__).resolve().parents[2]


class InvalidBuild(ValueError):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise InvalidBuild(reason)


def git(*args: str, timeout: int = 45) -> str:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=timeout
    )
    require(result.returncode == 0, "Git could not verify source provenance")
    return result.stdout


def commit(value: object) -> str:
    require(isinstance(value, str) and bool(re.fullmatch(r"[0-9a-f]{40}", value)),
            "Invalid source commit")
    return value


def ensure_commit(sha: str) -> None:
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"], cwd=ROOT,
        capture_output=True, timeout=10,
    )
    if result.returncode:
        git("fetch", "--no-tags", "--depth=1", "origin", sha)


def same_app_inputs(source: str, current: str) -> None:
    ensure_commit(source)
    result = subprocess.run(
        ["git", "diff", "--quiet", "--no-ext-diff", source, current, "--", *APP_PATHSPEC],
        cwd=ROOT, capture_output=True, timeout=30,
    )
    require(result.returncode == 0,
            "Tracked app inputs differ outside the root .github directory")


def verify_recipe(sha: str) -> None:
    """Check the actual source workflow, including legacy manifests without versions.

    The recipe has a deliberately fixed, simple YAML shape. Unsupported rewrites
    fail closed instead of treating text elsewhere in the workflow as a version.
    Gradle, dependency locks, native projects and assets are covered by git diff.
    """
    source = git("show", f"{sha}:{WORKFLOW}")
    match = re.search(r"(?ms)^  build-android:\n(.*?)(?=^  [\w-]+:\n|\Z)", source)
    require(match is not None, "Source workflow has no recognized Android build job")
    job = match.group(1)
    require(not re.search(r"^env:", source, re.M) and not re.search(r"^    env:", job, re.M),
            "Build-level environment overrides need a new reviewed recipe")
    require(re.search(r"^    runs-on: ubuntu-24\.04\s*$", job, re.M) is not None,
            "Build runner differs")
    steps = re.split(r"(?m)^      - ", job)[1:]
    actions = {
        "actions/setup-java@v4": {"distribution": "temurin", "java-version": "17"},
        "android-actions/setup-android@v4": {"cmdline-tools-version": "16111833"},
        "subosito/flutter-action@v2": {"channel": "stable", "flutter-version": "3.38.1"},
    }
    for action, settings in actions.items():
        selected = [step for step in steps if re.search(
            rf"(?m)^(?:        )?uses: {re.escape(action)}\s*$", step)]
        require(len(selected) == 1, "Build setup action differs")
        for key, expected in settings.items():
            values = re.findall(rf"(?m)^          {re.escape(key)}: ([^\n]+)$", selected[0])
            require(len(values) == 1 and values[0].strip().strip("\"'") == expected,
                    f"Build toolchain differs: {key}")
    commands = re.findall(r"(?m)^          (flutter build[^\n]*)$", job)
    require(commands == [BUILD_COMMAND], "APK build command differs")
    require("          flutter pub get\n" in job, "Dependency resolution recipe differs")
    require("          cp build/app/outputs/flutter-apk/app-debug.apk android-qa-build/reader.apk\n" in job,
            "APK output selection differs")


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_manifest(directory: Path, current: str, repository: str, *, legacy: bool = False) -> dict:
    data = json.loads((directory / "build.json").read_text())
    require(isinstance(data, dict), "Build manifest must be an object")
    original = commit(data.get("commit"))
    require(data.get("repository") == repository, "APK repository differs")
    require(data.get("package") == "com.quran.quran_double_page", "APK package differs")
    require(data.get("platform") == "android-x64" and data.get("reader_layout_qa") is True,
            "APK is not the Android x64 geometry build")
    require(data.get("sha256") == sha256(directory / "reader.apk"), "APK SHA-256 differs")
    if not legacy:
        require(data.get("validated_commit") == current, "APK was not validated for this commit")
        require(data.get("toolchain") == TOOLCHAIN, "APK toolchain provenance differs")
    elif "toolchain" in data:
        require(data["toolchain"] == TOOLCHAIN, "Cached APK toolchain differs")
    same_app_inputs(original, current)
    verify_recipe(original)
    verify_recipe(current)
    return data


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


def request_json(path: str, token: str) -> dict:
    request = urllib.request.Request(
        "https://api.github.com" + path,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "mushaf-android-qa"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def download_archive(repository: str, artifact_id: int, token: str, destination: Path) -> None:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/actions/artifacts/{artifact_id}/zip",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "mushaf-android-qa"},
    )
    try:
        urllib.request.build_opener(NoRedirect).open(request, timeout=20)
    except urllib.error.HTTPError as response:
        require(response.code == 302, "Artifact download did not return a signed location")
        location = response.headers.get("Location", "")
    else:
        raise InvalidBuild("Artifact download did not return a signed location")
    require(location.startswith("https://"), "Artifact download is not HTTPS")
    # Fetch the signed URL without forwarding the GitHub token to blob storage.
    with urllib.request.urlopen(location, timeout=30) as response, destination.open("wb") as output:
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            require(size <= MAX_ARCHIVE_BYTES, "Artifact archive exceeds the download limit")
            output.write(chunk)


def unpack(archive: Path, output: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        names = source.namelist()
        require(sorted(names) == ["build.json", "reader.apk"], "Unexpected artifact archive entries")
        require(source.getinfo("build.json").file_size <= 64 * 1024, "Build manifest is too large")
        require(0 < source.getinfo("reader.apk").file_size <= MAX_ARCHIVE_BYTES, "APK is too large")
        output.mkdir()
        for name in ("build.json", "reader.apk"):
            # Never use extract/extractall: only these literal destination names are allowed.
            with source.open(name) as src, (output / name).open("wb") as dest:
                shutil.copyfileobj(src, dest)


def write_manifest(directory: Path, data: dict) -> None:
    (directory / "build.json").write_text(json.dumps(data, indent=2) + "\n")


def reuse(directory: Path, current: str, repository: str) -> bool:
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("Artifact reuse unavailable; building the APK.")
        return False
    require(not directory.exists(), "APK output directory must be fresh")
    try:
        listing = request_json(
            f"/repos/{repository}/actions/artifacts?name={ARTIFACT}&per_page={MAX_CANDIDATES}", token)
    except (urllib.error.URLError, TimeoutError, ValueError):
        print("Artifact listing unavailable; building the APK.")
        return False
    for artifact in listing.get("artifacts", [])[:MAX_CANDIDATES]:
        artifact_id = artifact.get("id")
        run_id = artifact.get("workflow_run", {}).get("id")
        if (artifact.get("expired") or artifact.get("name") != ARTIFACT or
                type(artifact_id) is not int or type(run_id) is not int or
                str(run_id) == os.environ.get("GITHUB_RUN_ID")):
            continue
        try:
            run = request_json(f"/repos/{repository}/actions/runs/{run_id}", token)
            published = commit(run.get("head_sha"))
            require(run.get("path") == WORKFLOW and run.get("status") == "completed",
                    "Artifact is not from a completed run of this workflow")
            require(run.get("head_branch") == os.environ.get("GITHUB_REF_NAME"),
                    "Artifact was built on another branch")
            # The workflow may have failed after its build job uploaded a valid APK.
            same_app_inputs(published, current)
            verify_recipe(published)
            with tempfile.TemporaryDirectory(prefix="android-qa-artifact-") as temp:
                scratch = Path(temp)
                download_archive(repository, artifact_id, token, scratch / "artifact.zip")
                unpack(scratch / "artifact.zip", scratch / "build")
                data = verify_manifest(scratch / "build", current, repository, legacy=True)
                require(data.get("validated_commit", data["commit"]) == published,
                        "Manifest does not match the artifact run")
                data.update({"validated_commit": current, "toolchain": TOOLCHAIN, "reuse": {
                    "source_artifact_id": artifact_id, "source_run_id": run_id,
                    "source_run_commit": published,
                    "app_input_comparison": "all tracked files except root .github",
                }})
                write_manifest(scratch / "build", data)
                shutil.copytree(scratch / "build", directory)
            print(f"Reused artifact {artifact_id}: original build {data['commit'][:12]}, "
                  f"app inputs verified for {current[:12]}.")
            return True
        except (InvalidBuild, OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile):
            # Do not log authenticated URLs, redirect locations or response bodies.
            print(f"Artifact {artifact_id} is unavailable or incompatible; trying the next candidate.")
    print("No compatible recent APK artifact; building the APK.")
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("reuse", "stamp", "verify"))
    parser.add_argument("--directory", type=Path, default=Path("android-qa-build"))
    args = parser.parse_args()
    current = commit(os.environ.get("GITHUB_SHA"))
    repository = os.environ["GITHUB_REPOSITORY"]
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) is not None,
            "Invalid repository name")
    require(git("rev-parse", "HEAD").strip() == current, "Checkout differs from GITHUB_SHA")
    if args.command == "reuse":
        reused = reuse(args.directory, current, repository)
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
            output.write(f"reused={str(reused).lower()}\n")
    elif args.command == "stamp":
        verify_recipe(current)
        require(not git("status", "--porcelain", "--untracked-files=no", "--", *APP_PATHSPEC).strip(),
                "Build changed tracked app inputs")
        write_manifest(args.directory, {
            "commit": current, "validated_commit": current, "repository": repository,
            "sha256": sha256(args.directory / "reader.apk"),
            "package": "com.quran.quran_double_page", "platform": "android-x64",
            "reader_layout_qa": True, "toolchain": TOOLCHAIN,
        })
        print(f"Recorded fresh APK build {current[:12]}.")
    else:
        data = verify_manifest(args.directory, current, repository)
        print(f"Verified APK hash and unchanged app inputs: build {data['commit'][:12]}, "
              f"current {current[:12]}.")


if __name__ == "__main__":
    main()
