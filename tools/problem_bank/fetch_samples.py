#!/usr/bin/env python3
import argparse
import json
import re
import sys
from html.parser import HTMLParser
from urllib.request import urlopen, Request


class SimpleHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.text = []

    def handle_starttag(self, tag, attrs):
        self.stack.append(tag)

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()

    def handle_data(self, data):
        if self.stack and self.stack[-1] in ("p", "pre", "div", "span", "h1", "h2", "h3", "h4"):
            self.text.append(data)


def fetch(url):
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(req) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def parse_codeforces(html):
    # Extract title
    title_match = re.search(r"<div class=\"title\">\\s*([^<]+)</div>", html)
    title = title_match.group(1).strip() if title_match else "Codeforces Problem"
    # Extract statement text
    statement = extract_block(html, "statement")
    # Extract input/output sections
    input_desc = extract_block(html, "input-specification")
    output_desc = extract_block(html, "output-specification")
    # Extract sample tests
    samples = extract_cf_samples(html)
    return title, statement, input_desc, output_desc, samples


def extract_block(html, class_name):
    match = re.search(rf"<div class=\"{class_name}\">(.+?)</div>\\s*</div>", html, re.S)
    if not match:
        return ""
    inner = match.group(1)
    parser = SimpleHTML()
    parser.feed(inner)
    text = " ".join([t.strip() for t in parser.text if t.strip()])
    return normalize_spaces(text)


def extract_cf_samples(html):
    samples = []
    sample_re = re.finditer(r"<div class=\"sample-test\">(.+?)</div>\\s*</div>", html, re.S)
    for block in sample_re:
        b = block.group(1)
        inputs = re.findall(r"<div class=\"input\">\\s*<pre>(.+?)</pre>", b, re.S)
        outputs = re.findall(r"<div class=\"output\">\\s*<pre>(.+?)</pre>", b, re.S)
        for inp, out in zip(inputs, outputs):
            samples.append({"input": html_pre_to_text(inp), "output": html_pre_to_text(out)})
    return samples


def parse_atcoder(html):
    # Title
    title_match = re.search(r"<span class=\"h2\">\\s*([^<]+)</span>", html)
    title = title_match.group(1).strip() if title_match else "AtCoder Problem"
    # Statement sections
    statement = extract_atcoder_section(html, "Problem Statement")
    input_desc = extract_atcoder_section(html, "Input")
    output_desc = extract_atcoder_section(html, "Output")
    # Samples
    samples = extract_atcoder_samples(html)
    return title, statement, input_desc, output_desc, samples


def extract_atcoder_section(html, heading):
    pattern = rf"<h3>{re.escape(heading)}</h3>(.+?)(<h3>|</section>)"
    match = re.search(pattern, html, re.S)
    if not match:
        return ""
    inner = match.group(1)
    parser = SimpleHTML()
    parser.feed(inner)
    text = " ".join([t.strip() for t in parser.text if t.strip()])
    return normalize_spaces(text)


def extract_atcoder_samples(html):
    samples = []
    sample_in = re.findall(r"<h3>Sample Input \\d+</h3>\\s*<pre>(.+?)</pre>", html, re.S)
    sample_out = re.findall(r"<h3>Sample Output \\d+</h3>\\s*<pre>(.+?)</pre>", html, re.S)
    for inp, out in zip(sample_in, sample_out):
        samples.append({"input": html_pre_to_text(inp), "output": html_pre_to_text(out)})
    return samples


def html_pre_to_text(raw):
    text = raw.replace("<br />", "\n").replace("<br>", "\n")
    text = re.sub(r"<[^>]+>", "", text)
    return text.strip() + "\n"


def normalize_spaces(s):
    return re.sub(r"\\s+", " ", s).strip()


def build_entry(site, url, difficulty):
    html = fetch(url)
    if site == "codeforces":
        title, statement, input_desc, output_desc, samples = parse_codeforces(html)
    else:
        title, statement, input_desc, output_desc, samples = parse_atcoder(html)
    pid = url.rstrip("/").split("/")[-1]
    return {
        "id": pid,
        "title": title,
        "url": url,
        "difficulty": difficulty,
        "statement": statement,
        "input": input_desc,
        "output": output_desc,
        "tests": samples,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", choices=["codeforces", "atcoder"], required=True)
    ap.add_argument("--url", help="Single problem URL")
    ap.add_argument("--list", help="File containing URLs (one per line)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--difficulty", default="easy")
    args = ap.parse_args()

    urls = []
    if args.url:
        urls.append(args.url)
    if args.list:
        with open(args.list, "r") as f:
            urls += [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
    if not urls:
        print("No URLs provided", file=sys.stderr)
        return 2

    entries = []
    for u in urls:
        try:
            entries.append(build_entry(args.site, u, args.difficulty))
        except Exception as e:
            print(f"Failed to fetch {u}: {e}", file=sys.stderr)
    with open(args.out, "w") as f:
        json.dump(entries, f, indent=2)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

