#!/bin/bash

set +euo pipefail # Exit on any non-zero exit code, and error on use of undefined var

rm -rf ./dist && mkdir -p "dist"
version=$(
awk '/version:/ {
    pos=match($2, /[0-9]+\.[0-9]+\.[0-9]+/);
    print substr($2, pos, RLENGTH); }' plugin.yaml
)
echo "Version read from plugin.yaml: $version"
tar -czvf dist/dist-$version.tar.gz ./export_teamcity_messages.py ./html.tpl ./plugin.yaml ./trivy-teamcity-report
echo "Release archive created at dist/dist-$version.tar.gz"
 gh release create "$version" --generate-notes "./dist/dist-$version.tar.gz"