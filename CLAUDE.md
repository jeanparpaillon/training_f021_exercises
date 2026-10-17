# trainings_exercises

Exercises for the trainings whose slides are in the sibling repo
`../trainings/`, one subdirectory per training, matching the deck's directory
name there:

| Directory | Training | Slides |
| --- | --- | --- |
| `devops/` | DevOps for developers | `../trainings/devops/` |
| `f021/` | F021 — Advanced Kubernetes | `../trainings/f021/` |
| `f021bis/` | F021bis — Kubernetes in production | `../trainings/f021bis/` |
| `github/` | GitHub material (empty) | — |

Each training directory is self-contained (its own Makefiles, cluster setup,
`moduleN/` READMEs). Training-specific notes go in that directory's own
`CLAUDE.md` (`f021/CLAUDE.md`, `f021bis/CLAUDE.md`); they do not necessarily
apply to the others — clusters, consoles and conventions differ.
