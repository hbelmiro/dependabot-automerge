#!/usr/bin/env bats

# Unit tests for scripts/merge.sh.
# `gh` and `sleep` are mocked via a stub dir prepended to PATH.

setup() {
  TEST_TMP="$(mktemp -d)"
  STUB_DIR="${TEST_TMP}/bin"
  mkdir -p "${STUB_DIR}"
  export PATH="${STUB_DIR}:${PATH}"
  export LOG="${TEST_TMP}/calls.log"

  # Default valid environment for every test.
  export ACTOR='dependabot[bot]'
  export EVENT_NAME='pull_request'
  export MERGE_METHOD='merge'
  export DELETE_BRANCH='false'
  export RETRY_ON_ERROR='false'
  export MAX_RETRIES='5'
  export PR_URL='https://github.com/o/r/pull/1'

  # Mock sleep: record calls instead of waiting.
  cat > "${STUB_DIR}/sleep" <<'EOF'
#!/usr/bin/env bash
echo "sleep:$1" >> "${LOG}"
EOF
  chmod +x "${STUB_DIR}/sleep"
}

teardown() {
  rm -rf "${TEST_TMP}"
}

# Helper: mock gh that fails N times then succeeds (0 = always succeeds).
mock_gh() {
  local fails="$1"
  cat > "${STUB_DIR}/gh" <<EOF
#!/usr/bin/env bash
echo "gh:\$*" >> "\${LOG}"
if [[ ! -f "${TEST_TMP}/count" ]]; then echo 0 > "${TEST_TMP}/count"; fi
count=\$(cat "${TEST_TMP}/count")
count=\$((count + 1))
echo "\$count" > "${TEST_TMP}/count"
if [[ \$count -le ${fails} ]]; then exit 1; fi
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

@test "skips silently for non-Dependabot actor" {
  mock_gh 0
  export ACTOR='somebody-else'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping"* ]]
  # gh must never be called
  [ ! -f "${LOG}" ] || ! grep -q '^gh:' "${LOG}"
}

@test "skips for non-pull_request event" {
  mock_gh 0
  export EVENT_NAME='push'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping"* ]]
  [ ! -f "${LOG}" ] || ! grep -q '^gh:' "${LOG}"
}

@test "rejects invalid merge-method" {
  export MERGE_METHOD='fast-forward'
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
}

@test "rejects invalid retry-on-error" {
  export RETRY_ON_ERROR='yes'
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"retry-on-error"* ]]
}

@test "rejects non-numeric max-retries" {
  export MAX_RETRIES='many'
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"max-retries"* ]]
}

@test "rejects invalid delete-branch" {
  export DELETE_BRANCH='yes'
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"delete-branch"* ]]
}

@test "rejects unset delete-branch" {
  unset DELETE_BRANCH
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::delete-branch must be 'true' or 'false'"* ]]
}

@test "does not pass --delete-branch when false" {
  mock_gh 0
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  grep -q '^gh:pr merge --auto --merge https://github.com/o/r/pull/1$' "${LOG}"
}

@test "passes --delete-branch when enabled" {
  mock_gh 0
  export DELETE_BRANCH='true'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  grep -q '^gh:pr merge --auto --merge --delete-branch https://github.com/o/r/pull/1$' "${LOG}"
}

@test "passes --delete-branch with non-default merge method" {
  mock_gh 0
  export DELETE_BRANCH='true'
  export MERGE_METHOD='squash'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  grep -q '^gh:pr merge --auto --squash --delete-branch https://github.com/o/r/pull/1$' "${LOG}"
}

@test "keeps --delete-branch on every retry attempt" {
  mock_gh 2
  export DELETE_BRANCH='true'
  export RETRY_ON_ERROR='true'
  export MAX_RETRIES='5'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  # all 3 gh calls (2 failures + 1 success) must carry the flag
  [ "$(grep -c '^gh:pr merge --auto --merge --delete-branch ' "${LOG}")" -eq 3 ]
  [ "$(grep -c '^gh:' "${LOG}")" -eq 3 ]
}

@test "merges successfully on first attempt" {
  mock_gh 0
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  grep -q '^gh:pr merge --auto --merge https://github.com/o/r/pull/1$' "${LOG}"
  # no sleeps expected
  ! grep -q '^sleep:' "${LOG}"
}

@test "uses configured merge method" {
  mock_gh 0
  export MERGE_METHOD='squash'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  grep -q '^gh:pr merge --auto --squash ' "${LOG}"
}

@test "fails immediately when retry-on-error is false" {
  mock_gh 1
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed after 1 attempt"* ]]
  ! grep -q '^sleep:' "${LOG}"
}

@test "retries with exponential backoff and succeeds" {
  mock_gh 2
  export RETRY_ON_ERROR='true'
  export MAX_RETRIES='5'
  run scripts/merge.sh
  [ "$status" -eq 0 ]
  # 3 gh calls (2 failures + 1 success)
  [ "$(grep -c '^gh:' "${LOG}")" -eq 3 ]
  # backoff: 5s then 10s
  [ "$(grep -c '^sleep:' "${LOG}")" -eq 2 ]
  grep -q '^sleep:5$' "${LOG}"
  grep -q '^sleep:10$' "${LOG}"
}

@test "gives up after max-retries" {
  mock_gh 99
  export RETRY_ON_ERROR='true'
  export MAX_RETRIES='2'
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  # total attempts = max-retries + 1
  [ "$(grep -c '^gh:' "${LOG}")" -eq 3 ]
  [[ "$output" == *"failed after 3 attempt"* ]]
}

@test "zero max-retries means single attempt even with retry enabled" {
  mock_gh 99
  export RETRY_ON_ERROR='true'
  export MAX_RETRIES='0'
  run scripts/merge.sh
  [ "$status" -ne 0 ]
  [ "$(grep -c '^gh:' "${LOG}")" -eq 1 ]
}
