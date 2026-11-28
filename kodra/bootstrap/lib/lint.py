#!/usr/bin/env python3
"""Lint the bootstrap scripts and the workflow that runs them.

Both mistakes this catches have already cost a ten-minute CI cycle each:

  * a comment between backslash-continued arguments, which silently ends the
    command and drops every argument after it (bash's configure ran with no
    CFLAGS at all, and git's make with no NO_PTHREADS);
  * a shell script whose syntax is fine in isolation but which the workflow's
    YAML indentation mangles before bash ever sees it.

Run it before pushing:

    kodra/bootstrap/lib/lint.py
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BOOTSTRAP = ROOT / "kodra" / "bootstrap"
WORKFLOW = ROOT / ".github" / "workflows" / "kodra-bootstrap.yml"
# A recipe pins its source with a sha256, or a sha512 for npm registry tarballs,
# whose signed dist.integrity is a sha512.
RECIPE_KEYS = ("PKG_VERSION=", "PKG_URL=", "PKG_ARTIFACTS=", "build()")
PIN_KEYS = ("PKG_SHA256=", "PKG_SHA512=")


def report(problems: list[str], message: str) -> None:
    problems.append(message)


def check_files(problems: list[str]) -> list[Path]:
    scripts = sorted(BOOTSTRAP.glob("*.sh")) + [BOOTSTRAP / "lib" / "ci.sh"]
    recipes = sorted((BOOTSTRAP / "packages").glob("*.sh"))
    for path in scripts + recipes:
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines[:-1]):
            if line.rstrip().endswith("\\") and lines[index + 1].lstrip().startswith("#"):
                report(
                    problems,
                    f"{path.relative_to(ROOT)}:{index + 1}: comment after a line "
                    "continuation ends the command",
                )
        result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
        if result.returncode:
            report(problems, f"{path.relative_to(ROOT)}: {result.stderr.strip()}")
    for path in recipes:
        text = path.read_text()
        for key in RECIPE_KEYS:
            if key not in text:
                report(problems, f"{path.relative_to(ROOT)}: missing {key}")
        if not any(key in text for key in PIN_KEYS):
            report(problems, f"{path.relative_to(ROOT)}: missing a source digest")
    return scripts + recipes


def check_workflow(problems: list[str]) -> None:
    if not WORKFLOW.exists():
        # The probe job checks out only kodra/bootstrap, so the workflow is legitimately
        # absent there. The build job checks it out and runs this check for real.
        print("lint: workflow not in this checkout, skipped", file=sys.stderr)
        return
    try:
        import yaml
    except ImportError:
        # Not a failure: the file and syntax checks above are the ones that catch the
        # mistakes this tool exists for. The CI step installs pyyaml so this branch is
        # only reached in a bare environment.
        print("lint: pyyaml unavailable, workflow checks skipped", file=sys.stderr)
        return
    workflow = yaml.safe_load(WORKFLOW.read_text())
    for job_name, job in workflow.get("jobs", {}).items():
        for step in job.get("steps", []):
            script = step.get("run")
            if not script:
                continue
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as handle:
                handle.write(script)
                path = handle.name
            result = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
            Path(path).unlink()
            if result.returncode:
                report(
                    problems,
                    f"workflow job {job_name!r} step {step.get('name')!r}: "
                    f"{result.stderr.strip()}",
                )


def main() -> int:
    problems: list[str] = []
    check_files(problems)
    check_workflow(problems)
    if problems:
        for problem in problems:
            # GitHub's annotation syntax, because a step that fails without one cannot be
            # diagnosed from an environment without log access.
            print(f"::error title=lint::{problem}", file=sys.stderr)
        return 1
    print("lint: bootstrap scripts and workflow are clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
