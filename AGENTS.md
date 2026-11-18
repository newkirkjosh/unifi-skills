# UniFi skill catalog

This is a public, MIT-licensed catalog of reusable UniFi guidance. Everything committed is published on push, commit messages included. Keep credentials, network identifiers, personal information, machine paths and diagnostic run notes out of tracked files. Use placeholders. Network-specific knowledge stays in private project notes.

Read REVIEW.md before reviewing. Skills use the open Agent Skills format with matching directory/frontmatter names and explicit invocation descriptions. Keep scripts and references beside their skill. Preserve upstream attribution. Do not run live network operations to validate catalog changes.

Work in a worktree; install only from the main checkout after merge. Never bypass commit hooks. Run agentskills validate skills/unifi, scripts/check-descriptions.sh, scripts/check-refs.sh, scripts/check-private.sh, bash scripts/test-install.sh, and bash skills/unifi/scripts/test-scripts.sh before committing. Check shell syntax for every changed script.

PRs use conventional titles and squash merges. Credential helpers, permission/security guards and review policy changes require user merge unless explicitly authorized. Verify the local checks listed above, CI (the same checks plus a gitleaks scan of the full history) and independent review, and settle hosted findings on the candidate head before merging.
