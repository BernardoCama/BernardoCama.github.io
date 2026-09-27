#!/bin/bash
# Nightly Google Scholar citation refresh.
# Run from system crontab: 0 7 * * * cd <repo> && /bin/bash run_update.sh >> ~/.citations-update.log 2>&1
#
# NOTE: a GitHub Action ("Update Google Scholar citations") writes the same file.
# Two writers means the remote can diverge, so always rebase before pushing and
# never report success unless the push actually succeeded.
set -uo pipefail

cd /home/bernardo/Desktop/personal/PersonalSite || exit 1

python3 bin/update_scholar_citations.py || {
  echo "FAILED: update_scholar_citations.py exited $?"
  exit 1
}

if git diff --quiet _data/citations.yml; then
  echo 'No changes'
  exit 0
fi

git add _data/citations.yml
git commit -m 'chore: update Google Scholar citations' || {
  echo "FAILED: git commit exited $?"
  exit 1
}

# Remote may carry the GitHub Action's commit. Rebase onto it first; on a
# citations.yml conflict the only real difference is the last_updated timestamp,
# so prefer our newer local copy.
if ! git push 2>&1; then
  echo 'push rejected - fetching and rebasing onto remote'
  git fetch origin || { echo 'FAILED: git fetch'; exit 1; }
  if ! git -c core.editor=true rebase origin/main 2>&1; then
    unmerged=$(git diff --name-only --diff-filter=U)
    # Only auto-resolve when citations.yml is the ONLY conflicted file AND the
    # conflicting content is nothing but the last_updated timestamp. Real
    # citation-data divergence must be escalated, never silently overwritten.
    # During a rebase conflict git emits `diff --cc` combined output: conflict
    # markers carry a '++' prefix, and each side's content lines start with
    # '+' or ' ' in one of the two columns. Strip markers/headers, then check
    # that every remaining changed line is a last_updated line.
    conflict_body=$(git diff -- _data/citations.yml \
      | grep -vE '^(diff --cc|index |--- |\+\+\+ |@@)' \
      | grep -E '^[+ ]*\+' \
      | grep -vE '^\+*(<<<<<<<|=======|>>>>>>>)')
    offending=$(printf '%s\n' "$conflict_body" | grep -vE "last_updated:" | grep -c '[^[:space:]+]')
    if [ "$unmerged" = "_data/citations.yml" ] && [ "$offending" -eq 0 ]; then
      echo 'resolving citations.yml timestamp-only conflict in favour of local (newer) copy'
      git checkout --theirs -- _data/citations.yml || { echo 'FAILED: checkout --theirs'; git rebase --abort; exit 1; }
      git add _data/citations.yml
      git -c core.editor=true rebase --continue || { echo 'FAILED: rebase --continue'; git rebase --abort; exit 1; }
    else
      echo 'FAILED: conflict is not timestamp-only - aborting, needs a human'
      echo "conflicted files: $unmerged"
      git rebase --abort
      exit 1
    fi
  fi
  git push || { echo 'FAILED: push still rejected after rebase'; exit 1; }
fi

echo 'Citations updated and pushed'
