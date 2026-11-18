# UniFi skills

Agent skills for reading and diagnosing a UniFi network through its APIs, read-only by default.

## Install

```bash
npx skills add git@github.com:newkirkjosh/unifi-skills.git -g
```

The repository is private: the command needs a GitHub SSH key for an account with access to it. The `newkirkjosh/unifi-skills` shorthand clones over HTTPS and fails.

To edit the skills, clone the repository and run `scripts/install.sh` from the main checkout instead. It links the skills rather than copying them, so the checkout's `main` is what every session loads: make changes in a worktree, and after they merge, update the main checkout (`git pull`) and re-run the installer there. It refuses to replace an existing skill, so first delete any copies `npx skills` installed (`~/.agents/skills/<skill>` and its link in `~/.claude/skills`). If `unifi` is already installed from another catalog, remove that link through that catalog's installer first.

## Skills

| Skill | What it does |
|---|---|
| `unifi` | Chooses API access, inspects network evidence, and makes a change only after approval. |
