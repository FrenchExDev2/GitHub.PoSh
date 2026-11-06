# FrenchExDev2.GitHub.Tests.PoSh

Offline companion for the sibling GitHub module. Run it through `../scripts/Invoke-WorkspaceTests.ps1`, which creates a visible local monitor and saves reports outside the checkout. Do not invoke production GitHub rebases as tests.

The fake gh process runs through real QuietCli, journals exact argument vectors and returns deterministic JSON. Real Git scenarios build an independent upstream bare repository, fork bare repository and their working clones. Local rebase/push results are checked against Git parents, refs and file contents; conflict expectations are independently checked with Git. JSON scenarios additionally model server-only behavior such as review requirements and denied permissions.

Workspace import does not load the QuietCli Git companion. Only local Git fixtures load it lazily, immediately before their first native Git invocation; gh business operations require Core alone.

The regression corpus includes a stale PR base SHA hiding twelve upstream commits, three head commits, Unicode branch paths, forks, drafts, unknown mergeability, author restriction, pagination/deduplication, search ceilings, preflight reference changes, WhatIf, one-shot mutations, batch continuation, failed verification and timeout uncertainty.

Seed 346198 drives 4,000 policy property assertions and 1,000 malformed URL probes. Six in-memory targeted mutants challenge author filtering, divergence direction, current-base resolution, rebase arguments, WhatIf and one-shot execution. A verified baseline is required before mutation evaluation; invalid anchors/syntax, survivors and timeout fail qualification. This catalogue is targeted, not exhaustive mutation coverage.

Each mutant is restored in finally; the private fake transport is restored after the suite. All generated Git repositories are owned temporary fixtures. No real GitHub credentials, real gh process or network business calls are used. These tests do not qualify the hosted GitHub service.
