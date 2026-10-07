# 1.2.0 backlog — deferred QoL

Running list of **nice-to-have / polish** items deferred from 1.1.0 to keep that release focused on
the data-loss fix + correctness. Anything QoL that surfaces during 1.1.0 testing gets parked here
rather than expanding 1.1.0's scope/test burden.

(1.1.0 itself ships: the save-crash data-loss fix, draft persistence, the math task-month fix,
the 51014 reading fix, the IPP report-column fixes, the cohort QoL already built, and the cycle
time-binding fan-out.)

## Deferred QoL
- **Loading indicator on the Reports cycle-selector chips.** Clicking a cycle chip triggers a server
  round-trip (force-dynamic) with no feedback — add a loading state on the clicked chip (e.g. spinner /
  disabled-pending via `useLinkStatus`) so it's clear the report is refreshing.
