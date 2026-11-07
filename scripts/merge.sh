#!/usr/bin/env bash
set -euo pipefail

if [[ "${ACTOR:-}" != "dependabot[bot]" || "${EVENT_NAME:-}" != "pull_request" ]]; then
  echo "Not a Dependabot pull request (actor: ${ACTOR:-unset}, event: ${EVENT_NAME:-unset}). Skipping."
  exit 0
fi

if [[ ! "${MERGE_METHOD:-}" =~ ^(merge|squash|rebase)$ ]]; then
  echo "::error::Invalid merge-method '${MERGE_METHOD:-}' (must be merge, squash, or rebase)"
  exit 1
fi

if [[ "${RETRY_ON_ERROR:-}" != "true" && "${RETRY_ON_ERROR:-}" != "false" ]]; then
  echo "::error::retry-on-error must be 'true' or 'false'"
  exit 1
fi

if ! [[ "${MAX_RETRIES:-}" =~ ^[0-9]+$ ]]; then
  echo "::error::max-retries must be a non-negative integer"
  exit 1
fi

attempt=0
delay=5
until gh pr merge --auto --"${MERGE_METHOD}" "${PR_URL}"; do
  attempt=$((attempt + 1))
  if [[ "${RETRY_ON_ERROR}" != "true" || "${attempt}" -gt "${MAX_RETRIES}" ]]; then
    echo "::error::gh pr merge failed after ${attempt} attempt(s)"
    exit 1
  fi
  echo "gh pr merge failed (attempt ${attempt}/$((MAX_RETRIES + 1))); concurrent Dependabot PR race is common. Retrying in ${delay}s..."
  sleep "${delay}"
  delay=$((delay * 2))
done
