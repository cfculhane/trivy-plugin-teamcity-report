# trivy-plugin-teamcity-report

A Trivy plugin that exports an html report in a format used for teamcity, and outputs teamcity messages

Usage: `trivy teamcity-report OPERATION TARGET OUTPUTFILE [TRIVYPARAMS]`
Examples: 
- `trivy teamcity-report image python:3.8 output.html --scanners vuln`
- `trivy teamcity-report fs /path/to/dir output.html --scanners vuln,config`