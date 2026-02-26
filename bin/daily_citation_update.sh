#!/bin/bash
# Daily citation update + deploy
# Runs update_scholar_citations.py, commits if changed, pushes (triggers GitHub Pages rebuild)

set -e
cd "$(dirname "$0")/.."

echo "[$(date)] Starting citation update..."

# Update citations
python3 bin/update_scholar_citations.py

# Check if anything changed
if git diff --quiet _data/citations.yml; then
    echo "[$(date)] No citation changes detected."
    exit 0
fi

# Commit and push
git add _data/citations.yml
git commit -m "chore: update Google Scholar citations [$(date +%Y-%m-%d)]"
git push

echo "[$(date)] Citations updated and deployed."
