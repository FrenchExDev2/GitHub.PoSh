# FrenchExDev2.GitHub.PoSh

Exports `Get-GitHubPullRequestRebase` and `Invoke-GitHubPullRequestRebase`. Requires PowerShell Core 7.6+ and QuietCli Core >= 0.2.0. The module imports only PowerShell definitions and makes no native or network calls until a command is invoked.

Rebases use `gh pr update-branch <url> --rebase`: GitHub performs the rebase and branch update server-side. No local production checkout or Git push is involved, and Git's `--force-with-lease` flag is not passed to gh. See [WHY.md](../WHY.md) for the design rationale and concurrency limits.

Use `-All` (default), `-Org <names>`, `-Repository <owner/name values>` or `-PullRequest <github.com URLs>`. Scope sets are mutually exclusive and never change the authenticated-author restriction. Invoke supports `-WhatIf` and `-Confirm`; default confirmation impact is Medium.

Invoke additionally supports `-Ask` (wait for y/n per eligible PR) and `-Auto` (no additional prompt, also the default). Combining both throws before any CLI call. Invalid answers are requested again; n returns `Declined`. WhatIf skips both the prompt and mutation.

`src/Transport.ps1` owns bounded QuietCli execution; `Selection.ps1` owns complete discovery; `Policy.ps1` owns independent business decisions and typed reports; `Inspection.ps1` reads current references and immutable comparisons; `Commands.ps1` owns ShouldProcess and one-shot orchestration.

Typical decisions: `Eligible`, `UpToDate`, `NotOwned`, `Closed`, `Conflicts`, `Unknown`, `NotRebaseable`, `Error`. Mutation results: `NotAttempted`, `NotApplied`, `ChangedBeforeApply`, `Rebased`, `UpdatedStillBehind`, `Failed`, `AcceptedUnconfirmed`, `EffectUnconfirmed`. Inspect `CommandAccepted`, `EffectConfirmed`, `Reason` and the observed references together. Never infer success solely from a zero exit code or from a CI/review state.

The transport injection seam is private and used only by the companion; no public switch can replace gh with an arbitrary fixture client. No handler claiming general gh support is registered in QuietCli. The module implements only its explicit workflow through direct callbacks.
