# Why GitHubEcosystem exists

A pull request should present a focused contribution. Updating its branch should preserve that focus as the upstream project evolves. This package makes rebase the explicit update policy for the authenticated user's own open pull requests, across repositories and organizations.

## Keep the contribution reviewable

Repeatedly merging the base branch into a contribution adds synchronization commits and integration topology to its history. Rebasing instead places the contribution's commits on a newer base, keeping the series easier to review, cherry-pick and maintain. Conflicts are a normal part of integration; they do not justify silently switching to a merge.

A correct merge of the target branch does not inherently add other contributors' changes to GitHub's aggregate PR diff. GitHub uses a three-dot comparison from the merge base. The reason for choosing rebase is a focused contribution history, not a claim that every merge corrupts the diff.

The contributor's update policy is separate from the maintainers' final integration policy. This package updates PR branches; it does not choose how the upstream project accepts them.

## Spend review time on the change

For large, active projects such as VS Code and LLVM, the important costs include reviewer attention, conflict resolution and repeated CI execution. A merge does not duplicate the entire upstream history, and a rebase does not replay the entire repository: it replays the selected contribution commits. Neither repository size nor an unmeasured storage saving is sufficient to justify one policy.

Update when needed rather than chasing every upstream commit. A new branch head can trigger expensive builds and tests regardless of whether it came from merge or rebase. This package does not claim measured Git, network, storage or CI savings.

## Make automation explicit and observable

Discovery and inspection are separate from mutation. Selection remains restricted to the authenticated author's open PRs, including when a URL is supplied directly. Inspection reports divergence, conflicts, review requirements and CI independently.

Invocation supports preview and per-PR confirmation, revalidates references before updating, never substitutes a merge, and does not automatically retry an uncertain mutation. Conflicts require contributor intervention. A moved head is an observation, not proof that this process caused the update.

## Delegate the rebase to GitHub

This is a GitHub workflow module. It invokes `gh pr update-branch <url> --rebase` and delegates the rebase and branch update to GitHub's server-side implementation. GitHub applies its permissions, branch rules and service-side update checks; the module inspects the result and reports failures or uncertainty.

There is no local production checkout, local rebase or local Git push in this workflow. `--force-with-lease` belongs to `git push` when publishing a locally rewritten branch; it is not a required extra step for a hosted rebase request, and `gh pr update-branch` does not accept that flag. The package deliberately keeps the hosted workflow instead of introducing local repositories to reproduce it.

Preflight reference checks narrow the race window but do not themselves provide an atomic lease. Delegating the operation does not establish that the service offers guarantees identical to an explicit Git push lease. The module must report the observed outcome without claiming such equivalence. Conflicts remain visible and require contributor intervention; no merge fallback is allowed.

## Keep the evidence honest

Offline fixtures and disposable local repositories validate selection, decisions, argument vectors and observable local Git effects. They do not qualify GitHub's hosted implementation or demonstrate that a production PR was updated. Import, build and tests do not authorize production pushes, credential installation or publication.

## References

- [GitHub CLI: gh pr update-branch](https://cli.github.com/manual/gh_pr_update-branch)
- [Git: rebase](https://git-scm.com/docs/git-rebase)
- [Git: push and force-with-lease](https://git-scm.com/docs/git-push)
- [GitHub: PR branch comparisons](https://docs.github.com/en/pull-requests/reference/branches)
