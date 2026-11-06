# GitHubEcosystem

See [WHY.md](WHY.md) for the contribution-history policy, practical costs, and the decision to delegate rebasing to GitHub.

PowerShell Core 7.6+ workspace for inspecting and rebasing **your own open GitHub pull requests** through GitHub CLI and QuietCli Core >= 0.2.0.

The business project `FrenchExDev2.GitHub.PoSh` and its companion `FrenchExDev2.GitHub.Tests.PoSh` are direct siblings. This directory is the single Git root. QuietCli remains a separate dependency, not a copied engine.

```powershell
./scripts/Import-Workspace.ps1
Get-GitHubPullRequestRebase -All
Get-GitHubPullRequestRebase -Org microsoft
Get-GitHubPullRequestRebase -Repository microsoft/vscode,PowerShell/PowerShell
Get-GitHubPullRequestRebase -PullRequest https://github.com/microsoft/vscode/pull/346198
Invoke-GitHubPullRequestRebase -Org microsoft -WhatIf
Invoke-GitHubPullRequestRebase -Repository microsoft/vscode
Invoke-GitHubPullRequestRebase -All -Ask
Invoke-GitHubPullRequestRebase -All -Auto
```

`-All` is also the default: all repositories containing your open PRs, including forks and drafts. Selection parameters are mutually exclusive; organization, repository and URL filters accept arrays. An explicit URL never bypasses author or lifecycle checks. Only github.com is supported in this initial version. Authenticate separately with GitHub CLI; imports never launch commands or log in.

Invoke accepts mutually exclusive `-Ask` and `-Auto`. Ask requires `y` or `n` for each eligible PR, repeats invalid answers, and skips a declined PR. Auto does not ask; it is also the default when neither mode is supplied. `-WhatIf` never asks or mutates. Standard explicit `-Confirm` remains supported in either mode.

Get returns typed objects. Invoke revalidates every candidate, applies `ShouldProcess`, issues exactly one `gh pr update-branch <url> --rebase`, and observes the result. It never clones production repositories, resolves conflicts locally, substitutes a merge, or retries a mutation. Individual failures do not stop later PRs. Discovery failure stops the batch before its first mutation.

The current base reference is resolved independently from PR metadata. Its immutable SHA is compared to the PR head SHA: a stale `base.sha` must not hide divergence. Review requirements and CI results are reported separately and do not themselves prohibit rebase. The CLI still enforces server permissions and branch rules.

GitHub performs the rebase and branch update on the server. The module does not run a local Git push, so it does not use `--force-with-lease`; that Git push flag is not supported by `gh pr update-branch`. Server-side update handling belongs to GitHub, while the module revalidates its observations and reports the outcome.

Results include repository, number, URL, author, branches, observed SHAs/time, ahead/behind counts, mergeability, rebasability, review/CI, decision, result, reason, previous head and command acceptance. `Eligible` is a diagnostic, not a reservation of server state. Revalidation narrows but cannot eliminate the race between inspection and GitHub mutation. A changed head alone cannot prove which external actor moved it. An interrupted mutation has an unconfirmed effect and must not be replayed automatically.

Search is paginated up to GitHub's 1,000-result search ceiling. Incomplete search, a changing total or truncated response fails explicitly; narrow the scope instead of treating a partial set as complete. Responses are bounded to four million characters per stream and request, not silently truncated. Unknown rebasability is observed at most three times, one second apart.

## Offline qualification

```powershell
./scripts/Invoke-WorkspaceTests.ps1
# Optional explicit selected dependency:
./scripts/Invoke-WorkspaceTests.ps1 -CoreManifest /path/to/FrenchExDev2.QuietCli.Core.PoSh.psd1
```

The launcher prints the temporary report location and monitor reopening command. The dedicated local monitor identifies both projects, follows resizing, reports elapsed duration and counters, and closes after a saved terminal result. `-SkipMutation` is an explicitly limited development run; complete qualification does not use it. The whole run is limited to fifteen minutes.

The reusable CI workflow prepares Windows and Linux runs against an immutable external QuietCli revision. Set repository variable `QUIETCLI_REVISION` (or the manual workflow input) to a published 40-character commit containing Core >= 0.2.0. During implementation, local revision `2377c5b21e917d12887b9410a16ec1934d40a793` was unavailable remotely and public HEAD still declared Core 0.1.0. CI therefore fails explicitly until a compatible revision is accessible; it never falls back to the older engine. No dependency publication or push is performed here.

Fixtures combine JSON responses, a fake gh process through the real QuietCli engine, and two real local bare repositories with working clones. They use no GitHub account or network business request. They validate decisions, argument vectors and observable Git effects, **not GitHub's hosted rebase implementation**. See the companion README for the scenario and campaign scope.

## Sources and compatibility

Official contracts: [gh api](https://cli.github.com/manual/gh_api), [gh pr view](https://cli.github.com/manual/gh_pr_view), [gh pr update-branch](https://cli.github.com/manual/gh_pr_update-branch), [REST comparisons](https://docs.github.com/en/rest/commits/commits#compare-two-commits), [REST search](https://docs.github.com/en/rest/search/search#search-issues-and-pull-requests).

Required CLI capabilities are checked at invocation: version, update-branch help and `--rebase`. Runtime reports include the observed CLI version; fixture version strings are simulated and are not native-version qualification. PowerShell/Linux and additional CLI versions require their own evidence.

Installed help and capability inspection during development used gh 2.103.3 (2026-10-26) and Git 2.56.0.windows.3. No production PR was mutated for qualification.

Monitoring helpers are adapted from the sibling QuietCli workspace (`scripts/Watch-Tests.ps1` and `scripts/Monitor.Time.ps1`); their original attribution/license is preserved in `THIRD_PARTY_NOTICES.md` and `LICENSE`. No QuietCli engine source or binaries are included.
