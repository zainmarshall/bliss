# Problem Bank Tools

This folder contains scripts to build Bliss problem banks from competitive programming sites.

## fetch_samples.py
Downloads problem statements and **sample** tests from Codeforces or AtCoder and exports them to Bliss JSON format.

Usage:
```bash
python3 tools/problem_bank/fetch_samples.py --site codeforces --url https://codeforces.com/problemset/problem/4/A --out /tmp/cf.json
python3 tools/problem_bank/fetch_samples.py --site atcoder --url https://atcoder.jp/contests/abc086/tasks/abc086_a --out /tmp/atcoder.json
python3 tools/problem_bank/fetch_samples.py --site codeforces --list urls.txt --out /tmp/problems.json
```

Notes:
- This uses **samples only**. Full hidden tests are not publicly available for many platforms.
- If you want large datasets, run this script over a curated list of URLs and merge outputs.

