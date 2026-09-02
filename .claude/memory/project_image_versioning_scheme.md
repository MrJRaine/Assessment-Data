---
name: project_image_versioning_scheme
description: TODO to raise with the user — move prod image releases off commit-SHA tar names + the single mutable :token tag onto a real version scheme (semver tags).
metadata:
  type: project
---

**Open discussion the user asked to be reminded of (2026-09-02):** switch the
production image/deploy naming from commit-SHA-based artifacts to a proper
**version scheme**.

Current state: images are built as a single mutable tag `assessment-webapp:token`
and shipped as `assessment-webapp-<short-sha>.tar` (e.g. `-f4432b6`, `-c30095b`).

**Why it needs changing:** SHA-named tars are opaque and don't sort/compare
(you can't tell f4432b6 is older than c30095b without git); and every tar carries
the SAME `:token` tag, so on `podman load` the new image silently takes the tag and
the old one goes dangling — rollback works only because the old tar is kept around.

**How to apply when we discuss it:** propose semantic version tags per release
(`assessment-webapp:1.2.0` + optionally `:latest`), tar named by version
(`assessment-webapp-1.2.0.tar`), and a short CHANGELOG/tag-in-git mapping version →
commit. Keeps rollback explicit (run the prior version tag) and makes "what's in prod"
legible. Raise at next planning checkpoint or session wrap; don't let it slip.
