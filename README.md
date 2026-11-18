# UniFi skills

Agent skills for reading and diagnosing a UniFi network through its APIs, read-only by default.

## Install

```bash
npx skills add git@github.com:newkirkjosh/unifi-skills.git -g
```

The repository is private, so use the SSH URL: the `newkirkjosh/unifi-skills` shorthand clones over HTTPS and fails.

To edit the skills, clone the repository and run `scripts/install.sh` from the main checkout instead. It links the skills rather than copying them, so an edit takes effect on the next skill load.

## Skills

| Skill | What it does |
|---|---|
| `unifi` | Chooses API access, inspects network evidence, and makes a change only after approval. |
