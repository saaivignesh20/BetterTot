# Security Policy

## Supported Versions

BetterTot is currently a development preview. Security fixes are made on the
latest `main` branch; older builds are not supported.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately through
[GitHub Security Advisories](https://github.com/saaivignesh20/BetterTot/security/advisories/new).
Do not include real note contents, credentials, signing identities, or other
private user data in the report.

Include the affected commit or version, macOS version, reproduction steps, and
the expected impact. You should receive an acknowledgement within seven days.
Please do not publish details until a fix or coordinated disclosure plan is
available.

## Security Scope

Reports are especially useful when they concern:

- Loss, corruption, or unintended disclosure of local scratchpad data
- Unsafe file import, export, backup, or restore behavior
- Global-shortcut or Launch at Login privilege boundaries
- Update checks contacting an unexpected origin or opening an unsafe URL
- Release, signing, or CI credential exposure

BetterTot does not provide an automatic updater. Its update control only reads
public release metadata after an explicit user action.
