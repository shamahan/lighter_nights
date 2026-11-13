"""Builds the release archive publish/LighterNights-<version>.zip.

Run:  python tools/package.py
The archive holds one folder, LighterNights/, with only what the game needs:
the .toc, every file it lists, the icons and the license.
"""
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAME = "LighterNights"


def listed_files(toc_text):
    """File paths named in the .toc, with forward slashes."""
    files = []
    for line in toc_text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def main():
    toc_text = (ROOT / f"{NAME}.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", toc_text, re.M).group(1)
    icons = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Media").glob("*.png"))
    files = [f"{NAME}.toc", "LICENSE"] + listed_files(toc_text) + icons

    out = ROOT / "publish" / f"{NAME}-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for rel in files:
            archive.write(ROOT / rel, f"{NAME}/{rel}")
    print(f"wrote {out.relative_to(ROOT).as_posix()} ({len(files)} files)")


if __name__ == "__main__":
    main()
