import std/[os, strutils]

version = "0.8.2"
author = "Andrii Zahriadskyi"
description = "Trivy HTML reports and TeamCity build statistics"
license = "MIT"
srcDir = "src"
requires "nim >= 2.2.4"

proc buildStaticBinary() =
  if hostOS != "linux" or hostCPU != "amd64":
    raise newException(ValueError, "Release builds support Linux amd64 only")
  mkDir "build"
  exec "nim c -d:release --cc:gcc --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static --nimcache:build/nimcache/release --out:build/teamcity-report src/teamcity_report.nim"

task buildRelease, "Build a static Linux amd64 release binary (requires musl-gcc)":
  buildStaticBinary()

task release, "Build and package the release archive without publishing":
  var pluginVersion = ""
  for line in readFile("plugin.yaml").splitLines():
    if line.startsWith("version:"):
      pluginVersion = line.split(':', 1)[1].strip().strip(chars = {'"', '\''})
  if pluginVersion != version:
    raise newException(ValueError,
      "Versions in plugin.yaml and teamcity_report.nimble must match")
  let tag = getEnv("CI_COMMIT_TAG")
  if tag.len > 0 and tag != version:
    raise newException(ValueError,
      "Release tag must match plugin.yaml version (" & version & ")")
  buildStaticBinary()
  mkDir "dist"
  let stageDir = "build/release-package"
  mkDir stageDir
  exec "cp build/teamcity-report " & quoteShell(stageDir / "teamcity-report")
  exec "cp LICENSE " & quoteShell(stageDir / "LICENSE")
  let archive = "dist/trivy-plugin-teamcity-report-" & version & ".tar.gz"
  exec "tar -czf " & quoteShell(archive) & " -C " & quoteShell(stageDir) &
    " teamcity-report LICENSE"
  echo "Release archive created at " & archive

task test, "Run unit and CLI integration tests":
  mkDir "build"
  exec "nim c --nimcache:build/nimcache/app --out:build/teamcity-report src/teamcity_report.nim"
  exec "nim c --nimcache:build/nimcache/fake --out:build/trivy tests/fake_trivy.nim"
  exec "nim c -r --path:src --nimcache:build/nimcache/test --out:build/tests tests/all.nim"
