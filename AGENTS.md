# GitHubEcosystem monorepo

- One Git repository here. The business and companion test projects are direct siblings; never initialize child repositories.
- `FrenchExDev2.GitHub.PoSh` depends on QuietCli Core >= 0.2.0. `FrenchExDev2.GitHub.Tests.PoSh` depends on the business project. A business change validates both; a test change validates the test suite. Shared scripts and dependency changes validate everything.
- Use PowerShell Core 7.6+ with its normal profile and UTF-8 initialization. All text is UTF-8/LF. Code, comments and documentation are English.
- Use the selected local QuietCli Core through `scripts/Import-Workspace.ps1`. Never rebuild it implicitly, load an older Core or copy its engine here. Native business and fixture commands use `quiet` with explicit callbacks; read-only monitoring is the streaming exception.
- Import must remain offline and inert. Only Get/Invoke commands contact GitHub. Never run production Invoke commands during tests.
- Run `scripts/Invoke-WorkspaceTests.ps1`: offline JSON fixtures, real local upstream/fork repositories, generated properties, malformed-input fuzzing and in-memory targeted mutations. Never use real credentials or the real gh executable in fixtures.
- Local tests require the visible resizing PowerShell monitor. Saved reports and generated repositories belong outside the checkout under the system temporary directory. Headless is CI-only. Save every terminal state and close the dedicated monitor automatically.
- CI path workflows call the shared reusable qualification workflow. Windows/Linux qualification remains distinct from local Windows evidence. No skipped or unavailable campaign counts as a pass.
- Publication is not implemented or authorized by build/test. No implicit push, tag, remote creation, credential installation or profile change.
- Keep independent business assertions; record seed, fuzz/property counters and mutant outcomes separately. Never equate local Git simulation with qualification of GitHub's service.
