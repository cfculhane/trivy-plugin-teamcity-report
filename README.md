# trivy-plugin-teamcity-report

A Trivy plugin that exports an html report in a format used for teamcity, and outputs teamcity messages
### Installation

```shell
# Ensure the address starts with github, not https:// as this will fail
trivy plugin install github.com/zystem/trivy-plugin-teamcity-report
```

### Usage: 

```shell
trivy teamcity-report OPERATION TARGET OUTPUTFILE [TRIVYPARAMS]
```
### Examples: 
- `trivy teamcity-report image python:3.8 output.html --scanners vuln`
- `trivy teamcity-report fs /path/to/dir output.html --scanners vuln,config`

### Outputs

This plugin emits an HTML report that is modified from the one [supplied by trivy](https://github.com/aquasecurity/trivy/blob/main/contrib/html.tpl), with the following modifications:

- Sorted vulnerabilities from Critical -> Unknown
- Added description field
- Truncated links list to 300px with `...`
- Smaller font size

Example below:

![Example report](./docs/example_report.png)

It also emits build statistics that can then be read into teamcity, e.g.

```shell
##teamcity[buildStatisticValue key='VULNERABILITY_COUNT_UNKNOWN' value='1']
##teamcity[buildStatisticValue key='VULNERABILITY_COUNT_LOW' value='587']
##teamcity[buildStatisticValue key='VULNERABILITY_COUNT_MEDIUM' value='279']
##teamcity[buildStatisticValue key='VULNERABILITY_COUNT_HIGH' value='212']
##teamcity[buildStatisticValue key='VULNERABILITY_COUNT_CRITICAL' value='14']
```

### Nim implementation

The plugin is a single native executable built from `src/teamcity_report.nim`.
The HTML template is embedded at compile time. Runtime requires only `trivy` on
`PATH`; Python, jq, a shell, and Nim are not required. Release archives contain
one static Linux amd64 binary, suitable for both glibc and musl/Alpine images.

Comma-separated targets are scanned separately and merged in the given order.
Empty CSV entries are ignored; quote targets and options containing spaces.
Single-target mode retains the HTML scan, summary scan, and JSON statistics scan.
Statistics always request all severities. Trivy errors stop processing and retain
the Trivy exit code; temporary reports are removed on normal completion and errors.
Keys use `VULNERABILITY_COUNT_HIGH`, etc., without the old Python `Severity.` prefix.

### Development

Requires Nim 2.2.4 or newer and a C compiler. No Nim package dependencies.

```sh
nimble test -y
# Development build
nim c --out:build/teamcity-report src/teamcity_report.nim
# Run directly from source, compiling on demand
nim r src/teamcity_report.nim fs /path/to/project output.html --scanners vuln
```

Tests cover statistics, empty/null findings, merging, CLI validation, argument
quoting, target ordering, scan/conversion failures, invalid JSON, and cleanup.
A Nim fake Trivy keeps the suite offline and independent of vulnerability databases.

### Releases and CI/CD

The Woodpecker pipeline follows `nim-posixglob`: tests on manual runs, pull requests and pushes
to `main`, then a release build; tag events additionally publish a GitHub release.
The build step reruns the CLI tests against the static binary.
See [Woodpecker workflow syntax](https://woodpecker-ci.org/docs/usage/workflow-syntax).
Enable this repository in Woodpecker. In repository Settings → Secrets, add
`github_token` containing a GitHub token with Contents: Read and write access to
this repository, and enable the `tag` event for the secret. The release plugin receives
it through `settings.api-key.from_secret`. Set the allowed plugin image to
`woodpeckerci/plugin-release`. Do not use the internal clone credential `CI_NETRC_PASSWORD`.
See [Woodpecker secrets](https://woodpecker-ci.org/docs/usage/secrets).

To build locally on Linux amd64, install `musl-tools` (provides `musl-gcc`), then run:

```sh
nimble release -y
```

This creates `dist/trivy-plugin-teamcity-report-0.8.2.tar.gz` without publishing.
For a new release, update the version in `teamcity_report.nimble`, `plugin.yaml`
and its archive URL, commit, and push a matching tag such as `0.8.2` (no `v` prefix).
The pipeline checks version/tag consistency before publishing. Use a new tag for each release. Existing release metadata is preserved, and
uploading an asset with an existing name fails. Version 0.8.2 is prepared in this checkout.
