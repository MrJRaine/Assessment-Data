#!/bin/bash
# ---------------------------------------------------------------------------
# PreToolUse guard: Claude must NEVER execute anything against the Fabric
# warehouse -- not writes, not reads, not diagnostics, dev or live.
#
# Why this exists: on 2026-09-18 Claude used the app container's service
# principal to deploy two TVFs and run an UPDATE on DimSection, breaking a
# months-old agreement that the user runs all SQL. The protection had been
# purely procedural; this makes it mechanical, so it does not depend on
# Claude's judgment or on Claude's (demonstrably unreliable) self-reports
# about having internalised a rule.
#
# Deliberately over-blocks. A false positive costs one question to the user;
# a gap costs an unreviewed change to a warehouse holding student PII.
#
# Uses exit 2 + stderr rather than the JSON permissionDecision form on
# purpose: there is no jq on this machine, and a hand-rolled JSON payload that
# fails to parse could fail OPEN. Exit 2 cannot fail open.
# ---------------------------------------------------------------------------

INPUT=$(cat)

# Windows paths arrive escaped; normalise so patterns match either way.
NORM="${INPUT//\\//}"

BLOCK=""

case "$NORM" in
  *database.windows.net*)   BLOCK="a direct Fabric SQL endpoint (database.windows.net)" ;;
  *ClientSecretCredential*) BLOCK="the service-principal SQL auth path (ClientSecretCredential)" ;;
  *FABRIC_SQL_*)            BLOCK="the warehouse connection settings (FABRIC_SQL_*)" ;;
  *sqlcmd*|*Invoke-Sqlcmd*) BLOCK="a command-line SQL client (sqlcmd)" ;;
esac

# The exact route used in the 2026-09-18 incident: a script run inside the app
# container, which holds live service-principal credentials. Container
# lifecycle itself stays allowed -- build / run / logs / ps are Claude's lane.
if [ -z "$BLOCK" ]; then
  case "$NORM" in
    *podman*exec*)
      case "$NORM" in
        *node*|*.cjs*|*.js*|*.sql*)
          BLOCK="a script executed inside the app container (podman exec + node/.cjs/.sql)" ;;
      esac
      ;;
  esac
fi

if [ -n "$BLOCK" ]; then
  cat >&2 <<EOF
BLOCKED by .claude/hooks/block-warehouse-sql.sh

This command matched $BLOCK.

CLAUDE.md > "Authority and Access" is binding: you NEVER execute anything
against the Fabric warehouse -- not writes, not reads, not diagnostics, not
metadata checks, dev or live, by any mechanism. There is no exception for
"just checking", "only synthetic rows", or "verifying my own fix".

Do this instead: write the SQL to a tracked file in the repo, link it, state
what it does and which tables/fields it touches, and hand it to the user to
run. Then wait for their results.

If this is a false positive (e.g. grepping a source file for a string), say
what you were trying to do and ask the user -- do not try to reword the
command to get around this guard.
EOF
  exit 2
fi

exit 0
