#!/bin/bash

set +euo pipefail # Exit on any non-zero exit code, and error on use of undefined var
dist_dir="dist/teamcity-report"
rm -rf ./dist && mkdir -p "$dist_dir"
version=$(
  awk '/version:/ {
    pos=match($2, /[0-9]+\.[0-9]+\.[0-9]+/);
    print substr($2, pos, RLENGTH); }' plugin.yaml
)
echo "Version read from plugin.yaml: $version"
cp export_teamcity_messages.py html.tpl plugin.yaml trivy-teamcity-report "$dist_dir"
cd dist && tar -czvf "teamcity-report-$version.tar.gz" "teamcity-report" && cd ..
echo "Release archive created at dist/dist-$version.tar.gz"
gh release create "$version" --generate-notes "./dist/dist-$version.tar.gz"
