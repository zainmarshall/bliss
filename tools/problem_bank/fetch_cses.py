#!/usr/bin/env python3
"""Fetch CSES problems with full test cases (from problem pages).

CSES provides sample test cases on each problem page. This scraper extracts:
- Problem title
- Statement (with raw LaTeX math preserved for client-side rendering)
- Input/Output descriptions
- Constraints
- Sample test cases

Usage:
    python3 fetch_cses.py --url https://cses.fi/problemset/task/1640 --out problems.json
    python3 fetch_cses.py --list cses_urls.txt --out problems.json
    python3 fetch_cses.py --set introductory --out problems.json
"""

import argparse
import json
import re
import sys
import time
from urllib.request import urlopen, Request

# Well-known CSES problem sets with URLs and difficulties
CSES_SETS = {
    "introductory": {
        "difficulty": "easy",
        "urls": [
            "https://cses.fi/problemset/task/1068",  # Weird Algorithm
            "https://cses.fi/problemset/task/1083",  # Missing Number
            "https://cses.fi/problemset/task/1069",  # Repetitions
            "https://cses.fi/problemset/task/1094",  # Increasing Array
            "https://cses.fi/problemset/task/1070",  # Permutations
            "https://cses.fi/problemset/task/1071",  # Number Spiral
            "https://cses.fi/problemset/task/1072",  # Two Knights
            "https://cses.fi/problemset/task/1092",  # Two Sets
            "https://cses.fi/problemset/task/1617",  # Bit Strings
            "https://cses.fi/problemset/task/1618",  # Trailing Zeros
            "https://cses.fi/problemset/task/1754",  # Coin Piles
            "https://cses.fi/problemset/task/2205",  # Gray Code
            "https://cses.fi/problemset/task/2165",  # Tower of Hanoi
        ],
    },
    "sorting": {
        "difficulty": "easy",
        "urls": [
            "https://cses.fi/problemset/task/1621",  # Distinct Numbers
            "https://cses.fi/problemset/task/1084",  # Apartments
            "https://cses.fi/problemset/task/1090",  # Ferris Wheel
            "https://cses.fi/problemset/task/1091",  # Concert Tickets
            "https://cses.fi/problemset/task/1619",  # Restaurant Customers
            "https://cses.fi/problemset/task/1629",  # Movie Festival
            "https://cses.fi/problemset/task/1640",  # Sum of Two Values
            "https://cses.fi/problemset/task/1643",  # Maximum Subarray Sum
            "https://cses.fi/problemset/task/1074",  # Stick Lengths
            "https://cses.fi/problemset/task/2183",  # Missing Coin Sum
            "https://cses.fi/problemset/task/2216",  # Collecting Numbers
            "https://cses.fi/problemset/task/1164",  # Room Allocation
        ],
    },
    "dynamic": {
        "difficulty": "medium",
        "urls": [
            "https://cses.fi/problemset/task/1633",  # Dice Combinations
            "https://cses.fi/problemset/task/1634",  # Minimizing Coins
            "https://cses.fi/problemset/task/1635",  # Coin Combinations I
            "https://cses.fi/problemset/task/1636",  # Coin Combinations II
            "https://cses.fi/problemset/task/1637",  # Removing Digits
            "https://cses.fi/problemset/task/1638",  # Grid Paths
            "https://cses.fi/problemset/task/2413",  # Counting Towers
            "https://cses.fi/problemset/task/1744",  # Rectangle Cutting
            "https://cses.fi/problemset/task/1745",  # Money Sums
            "https://cses.fi/problemset/task/1097",  # Removal Game
        ],
    },
    "graph": {
        "difficulty": "medium",
        "urls": [
            "https://cses.fi/problemset/task/1192",  # Counting Rooms
            "https://cses.fi/problemset/task/1666",  # Building Roads
            "https://cses.fi/problemset/task/1667",  # Message Route
            "https://cses.fi/problemset/task/1668",  # Building Teams
            "https://cses.fi/problemset/task/1669",  # Round Trip
            "https://cses.fi/problemset/task/1671",  # Shortest Routes I
            "https://cses.fi/problemset/task/1672",  # Shortest Routes II
            "https://cses.fi/problemset/task/1202",  # Investigation
            "https://cses.fi/problemset/task/1750",  # Planets Queries I
        ],
    },
    "trees": {
        "difficulty": "hard",
        "urls": [
            "https://cses.fi/problemset/task/1674",  # Subordinates
            "https://cses.fi/problemset/task/1130",  # Tree Matching
            "https://cses.fi/problemset/task/1131",  # Tree Diameter
            "https://cses.fi/problemset/task/1132",  # Tree Distances I
            "https://cses.fi/problemset/task/1133",  # Tree Distances II
            "https://cses.fi/problemset/task/1688",  # Company Queries I
        ],
    },
}


def fetch(url):
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def extract_title(html):
    # CSES titles are in <h1> inside content area
    match = re.search(r'<h1>\s*(.+?)\s*</h1>', html, re.S)
    if match:
        title = re.sub(r'<[^>]+>', '', match.group(1)).strip()
        return title
    return "CSES Problem"


def extract_content_div(html):
    """Extract the main content div (class='md')."""
    match = re.search(r'<div class="md">(.*?)</div>\s*</div>', html, re.S)
    if match:
        return match.group(1)
    return html


def clean_html(html_fragment):
    """Convert HTML fragment to plain text, preserving math class spans as LaTeX."""
    text = html_fragment.replace("<br />", "\n").replace("<br>", "\n")
    # Preserve math spans - extract their text content (LaTeX)
    text = re.sub(r'<span class="math[^"]*">([^<]*)</span>', r'\1', text)
    # <code> → backtick-like content
    text = re.sub(r'<code>([^<]*)</code>', r'\1', text)
    # <li> → bullet
    text = re.sub(r'<li>\s*', '• ', text)
    # <p> → newline separation
    text = re.sub(r'</p>\s*<p>', '\n\n', text)
    # Remove remaining HTML tags
    text = re.sub(r'<[^>]+>', '', text)
    # Decode HTML entities
    text = text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
    text = text.replace("&le;", "≤").replace("&ge;", "≥")
    text = text.replace("&nbsp;", " ").replace("&#39;", "'")
    # Normalize whitespace within lines but preserve line breaks
    lines = text.split("\n")
    lines = [re.sub(r'[ \t]+', ' ', line).strip() for line in lines]
    text = "\n".join(lines)
    # Collapse multiple blank lines
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def parse_cses(html, url, difficulty):
    title = extract_title(html)
    task_id = url.rstrip("/").split("/")[-1]

    content = extract_content_div(html)

    # CSES uses <h1 id="input">Input</h1>, <h1 id="output">Output</h1>, etc.
    # Split content by <h1> headers
    sections = re.split(
        r'<h1[^>]*>\s*(Input|Output|Constraints|Example|Limits)\s*</h1>',
        content, flags=re.S | re.I
    )

    # sections[0] = statement (before first <h1>)
    statement = clean_html(sections[0]) if sections else ""

    input_desc = ""
    output_desc = ""
    constraints = ""
    example_html = ""

    i = 1
    while i < len(sections) - 1:
        header = sections[i].strip().lower()
        body = sections[i + 1]
        if header == "input":
            input_desc = clean_html(body)
        elif header == "output":
            output_desc = clean_html(body)
        elif header in ("constraints", "limits"):
            constraints = clean_html(body)
        elif header == "example":
            example_html = body
        i += 2

    # Extract samples from example section (or full content as fallback)
    sample_source = example_html if example_html else content
    pres = re.findall(r'<pre>(.*?)</pre>', sample_source, re.S)
    samples = []
    for j in range(0, len(pres) - 1, 2):
        inp = clean_html(pres[j]).strip() + "\n"
        out = clean_html(pres[j + 1]).strip() + "\n"
        samples.append({"input": inp, "output": out})

    return {
        "id": f"cses-{task_id}",
        "title": title,
        "url": url,
        "difficulty": difficulty,
        "statement": statement,
        "input": input_desc if input_desc else None,
        "output": output_desc if output_desc else None,
        "constraints": constraints if constraints else None,
        "tests": samples,
    }


def fetch_problem(url, difficulty):
    html = fetch(url)
    return parse_cses(html, url, difficulty)


def main():
    ap = argparse.ArgumentParser(description="Fetch CSES problems for Bliss")
    ap.add_argument("--url", help="Single problem URL")
    ap.add_argument("--list", help="File containing URLs (one per line)")
    ap.add_argument("--set", choices=list(CSES_SETS.keys()),
                    help="Fetch a predefined set of CSES problems")
    ap.add_argument("--all-sets", action="store_true",
                    help="Fetch all predefined CSES sets")
    ap.add_argument("--out", required=True, help="Output JSON file")
    ap.add_argument("--difficulty", default=None,
                    help="Override difficulty (easy/medium/hard)")
    ap.add_argument("--delay", type=float, default=1.0,
                    help="Delay between requests in seconds")
    args = ap.parse_args()

    jobs = []  # list of (url, difficulty)

    if args.url:
        jobs.append((args.url, args.difficulty or "easy"))

    if args.list:
        with open(args.list) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    jobs.append((line, args.difficulty or "easy"))

    if args.set:
        s = CSES_SETS[args.set]
        diff = args.difficulty or s["difficulty"]
        for u in s["urls"]:
            jobs.append((u, diff))

    if args.all_sets:
        for name, s in CSES_SETS.items():
            diff = args.difficulty or s["difficulty"]
            for u in s["urls"]:
                jobs.append((u, diff))

    if not jobs:
        print("No URLs provided. Use --url, --list, --set, or --all-sets.", file=sys.stderr)
        return 2

    entries = []
    for i, (url, diff) in enumerate(jobs):
        try:
            print(f"[{i+1}/{len(jobs)}] Fetching {url} ...", file=sys.stderr)
            entry = fetch_problem(url, diff)
            entries.append(entry)
            if i < len(jobs) - 1:
                time.sleep(args.delay)
        except Exception as e:
            print(f"  FAILED: {e}", file=sys.stderr)

    with open(args.out, "w") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)

    print(f"Wrote {len(entries)} problems to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
