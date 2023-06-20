#!/bin/bash

staged_files=$(git diff --cached --name-only --diff-filter=ACM)

for file in $staged_files; do
  if [[ $file == *.sol ]] || [[ $file == *.t.sol ]]; then
    forge fmt "$file"
    git add "$file"
  fi
done
