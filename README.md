# Dependabot Auto-merge

A GitHub Action that enables [auto-merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) on Dependabot pull requests, so they merge automatically once all required checks pass.

When two Dependabot PRs are merged around the same time, the second merge often fails because the first one invalidated the base ref. This action retries with exponential backoff to handle that race.

## Usage

```yaml
name: Dependabot Auto-merge

on: pull_request

permissions:
  contents: write
  pull-requests: write

jobs:
  dependabot:
    runs-on: ubuntu-latest
    steps:
      - uses: hbelmiro/dependabot-automerge@v1
```

That's it — the action checks `github.actor` itself and does nothing on PRs that aren't from `dependabot[bot]`.

## Requirements

- The repository must have **Settings → General → Pull Requests → Allow auto-merge** enabled.
- The workflow needs `contents: write` and `pull-requests: write` permissions.
- `gh pr merge --auto` only merges once required reviews and status checks pass — your existing CI still gates the merge.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `github-token` | no | `github.token` | Token used to enable auto-merge. |
| `merge-method` | no | `merge` | Merge method: `merge`, `squash`, or `rebase`. |
| `delete-branch` | no | `false` | Delete the pull request branch after merge. |
| `retry-on-error` | no | `true` | Retry with exponential backoff when the merge command fails (e.g. concurrent Dependabot PRs racing to update the base branch). |
| `max-retries` | no | `5` | Maximum number of retries (total attempts = `max-retries` + 1). The delay doubles each attempt, starting at 5s. |

## Example with all inputs

```yaml
steps:
  - uses: hbelmiro/dependabot-automerge@v1
    with:
      merge-method: squash
      delete-branch: true
      retry-on-error: true
      max-retries: 3
```

## License

[Apache 2.0](LICENSE)
