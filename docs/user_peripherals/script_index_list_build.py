#!/usr/bin/env python3
import os, re, json
from pathlib import Path

BASE_DIR = Path(__file__).parent
OUT_MD   = BASE_DIR / "index_list.md"
OUT_JSON = BASE_DIR / "index_list.json"

REPO_URL = "https://github.com/TinyTapeout/ttsky25a-tinyQV"
BRANCH   = "main"
REL_PATH = "docs/user_peripherals"

H1_RE = re.compile(r"^\s*#\s+(.+?)\s*$", re.MULTILINE)
AUTHOR_LINE_RE = re.compile(r"^\s*(?:Author|Authors?)\s*:\s*(.+?)\s*$", re.IGNORECASE)

def strip_html_comments(md: str) -> str:
    return re.sub(r"<!--.*?-->", "", md, flags=re.DOTALL)

def derive_name_from_filename(name: str) -> str:
    stem = Path(name).stem
    stem = re.sub(r"^\d+\s*[-_ ]*\s*", "", stem)
    stem = stem.replace("_", " ").replace("-", " ").strip()
    return stem if stem else None

def extract_number_from_filename(path: Path):
    m = re.match(r"^(\d+)", path.stem)
    return int(m.group(1)) if m else None

def classify_type(number: int) -> str:
    if number is None:
        return "Simple"
    if number < 16 or number in (32,33,34,35,36,37,38,39): #hardcoded 32 - 39 to be full peripherals
        return "Full"
    return "Simple"

def extract_from_md(path: Path):
    raw = path.read_text(encoding="utf-8", errors="ignore")
    md = strip_html_comments(raw)

    number = extract_number_from_filename(path)
    data = {
        "number": number,
        "name": None,
        "author": None,
        "file": path.name,
        "type": classify_type(number)
    }

    m = H1_RE.search(md)
    data["name"] = m.group(1).strip() if m else derive_name_from_filename(path.name)

    for line in md.splitlines():
        am = AUTHOR_LINE_RE.match(line)
        if am:
            data["author"] = am.group(1).strip()
            break

    return data

def main():
    items = []
    for mdfile in BASE_DIR.glob("*.md"):
        if mdfile.name == "INDEX.md":
            continue
        items.append(extract_from_md(mdfile))

    items.sort(key=lambda d: (d["number"] if d["number"] is not None else 999999, (d["name"] or "").lower()))

    # Markdown index
    with OUT_MD.open("w", encoding="utf-8") as f:
        f.write("# Peripheral Index\n\n")
        f.write("| # | Name | Author(s) | Type | File |\n")
        f.write("|---:|---|---|---|---|\n")
        for it in items:
            num = it["number"] if it["number"] is not None else ""
            name = it["name"] or ""
            author = it["author"] or ""
            # full GitHub link
            url = f"{REPO_URL}/blob/{BRANCH}/{REL_PATH}/{it['file']}"
            f.write(f"| {num} | {name} | {author} | {it['type']} | [{it['file']}]({url}) |\n")

    # JSON
    with OUT_JSON.open("w", encoding="utf-8") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)

    print(f"Indexed {len(items)} peripherals")

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as sf, OUT_MD.open("r", encoding="utf-8") as md:
            sf.write(md.read())

if __name__ == "__main__":
    main()
