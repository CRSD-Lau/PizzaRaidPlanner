# Security policy

## Supported version

Only the newest published release is considered for security review. This is a source-available reference project, not a hosted service or supported public SaaS product.

## Private reporting

Do not open a public issue or pull request for a suspected vulnerability. Use GitHub's private **Report a vulnerability** flow when it is enabled for the repository. Include the affected version, relevant component, impact, and a minimal reproduction that contains no real credentials or raid data.

The upstream repository does not promise a response time, fix, or public advisory. Reports may be closed if they concern a fork, a modified workbook, third-party hosting, private-server behavior, or unsupported deployment choices.

## Secrets that must never be committed

- Discord webhook URLs
- Apps Script deployment URLs or deployment IDs
- Desktop upload tokens or encrypted token blobs
- Google workbook IDs tied to a live raid workbook
- `%LOCALAPPDATA%\PizzaRaidPlanner` configuration and audit files
- WoW `WTF`, SavedVariables, combat logs, account names, or character histories
- OAuth tokens, GitHub tokens, API keys, private keys, or service-account files

Run `scripts/Test-PublicRepository.ps1` before every commit and release.
