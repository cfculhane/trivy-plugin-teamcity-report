#!/bin/bash

set +euo pipefail # Exit on any non-zero exit code, and error on use of undefined var
rm -rf ./dist && mkdir -p ./dist
version=$(
  awk '/version:/ {
    pos=match($2, /[0-9]+\.[0-9]+\.[0-9]+/);
    print substr($2, pos, RLENGTH); }' plugin.yaml
)
dist_filename="trivy-plugin-teamcity-report-$version.tar.gz"

echo "Version read from plugin.yaml: $version"
tar -czvf "./dist/$dist_filename" export_teamcity_messages.py html.tpl teamcity-report
echo "Release archive created at dist/$dist_filename"
gh release create "$version" --generate-notes "./dist/$dist_filename"
