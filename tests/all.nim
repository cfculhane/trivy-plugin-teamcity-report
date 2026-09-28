import std/[json, os, osproc, strutils, tempfiles, unittest]
import teamcity_report

suite "TeamCity statistics":
  test "counts every severity and separates misconfigurations":
    let doc = %*{"Results": [
      {"Class": "os-pkgs", "Vulnerabilities": [
        {"Severity": "HIGH"}, {"Severity": "HIGH"}, {"Severity": "LOW"}]},
      {"Class": "config", "Misconfigurations": [{"Severity": "CRITICAL"}]}]}
    let messages = statisticMessages(doc)
    check messages.len == 10
    check messages[0] == "##teamcity[buildStatisticValue key='VULNERABILITY_COUNT_UNKNOWN' value='0']"
    check messages[1].endsWith("value='1']")
    check messages[3].endsWith("value='2']")
    check messages[9] == "##teamcity[buildStatisticValue key='MISCONFIGURATION_COUNT_CRITICAL' value='1']"
    check "Severity." notin messages.join("\n")
  test "missing and null findings produce zero counts":
    let doc = %*{"Results": [{"Class": "os-pkgs", "Vulnerabilities": nil},
      {"Class": "config"}]}
    let messages = statisticMessages(doc)
    check messages.len == 10
    for message in messages: check message.endsWith("value='0']")
  test "empty reports have no statistics":
    for doc in [newJObject(), %*{"Results": nil}, %*{"Results": []}]:
      check statisticMessages(doc).len == 0
  test "malformed report shapes are rejected":
    for doc in [%*[], %*{"Results": "wrong"}, %*{"Results": [1]}]:
      expect ValueError: discard statisticMessages(doc)
  test "merge preserves first metadata and target order without mutating input":
    let first = %*{"ArtifactName": "first", "Results": [{"Target": "one"}]}
    let second = %*{"ArtifactName": "second", "Results": [{"Target": "two"}]}
    let merged = mergeReports([first, %*{"Results": nil}, second])
    check merged["ArtifactName"].getStr() == "first"
    check merged["Results"].len == 2
    check merged["Results"][1]["Target"].getStr() == "two"
    check first["Results"].len == 1

let project = getCurrentDir()
let sandbox = createTempDir("teamcity-tests-", "")
let oldPath = getEnv("PATH")
let oldTmp = getEnv("TMPDIR")
createDir(sandbox / "scratch")
copyFile(project / "build/teamcity-report", sandbox / "report with spaces")
setFilePermissions(sandbox / "report with spaces", {fpUserRead, fpUserWrite, fpUserExec})
putEnv("PATH", project / "build" & ":" & oldPath)
putEnv("TMPDIR", sandbox / "scratch")
putEnv("TRIVY_TEST_LOG", sandbox / "calls")
putEnv("TRIVY_TEST_MERGED", sandbox / "merged.json")
proc invoke(args: seq[string]): tuple[output: string, exitCode: int] =
  execCmdEx(quoteShellCommand(@[sandbox / "report with spaces"] & args))
proc calls(): seq[seq[string]] =
  if fileExists(sandbox / "calls"):
    for line in lines(sandbox / "calls"):
      var args: seq[string]
      for item in parseJson(line): args.add(item.getStr())
      result.add(args)
proc scratchEmpty(): bool =
  for entry in walkDir(sandbox / "scratch"): return false
  true

suite "CLI with fake Trivy":
  setup:
    writeFile(sandbox / "calls", "")
    delEnv("TRIVY_TEST_FAIL")
    delEnv("TRIVY_TEST_INVALID")
  test "help and invalid arguments do not invoke Trivy":
    for args in [newSeq[string](), @["-h"], @["--help"]]:
      check invoke(args).exitCode == 0
    for args in [@["fs"], @["fs", "a", ""], @["fs", ",,,", "out"]]:
      check invoke(args).exitCode != 0
    check calls().len == 0
  test "single target preserves argument boundaries and embeds template":
    let target = "path with spaces;$(touch SHOULD_NOT_EXIST)"
    let res = invoke(@["fs", target, sandbox / "out file.html", "--ignorefile", "ignore file"])
    check res.exitCode == 0
    check res.output.contains("VULNERABILITY_COUNT_HIGH' value='1'")
    check fileExists(sandbox / "out file.html")
    check calls().len == 3
    for args in calls():
      check target in args
      check "ignore file" in args
    check scratchEmpty()
  test "CSV skips empty targets and preserves order for more than ten targets":
    var targets: seq[string]
    for i in 0..11: targets.add("target " & $i)
    let res = invoke(@["image", "," & targets.join(",") & ",,", sandbox / "multi.html"])
    check res.exitCode == 0
    check res.output.contains("VULNERABILITY_COUNT_HIGH' value='12'")
    let merged = parseFile(sandbox / "merged.json")
    check merged["ArtifactName"].getStr() == targets[0]
    for i, target in targets: check merged["Results"][i]["Target"].getStr() == target
    check calls().len == 14
    check scratchEmpty()
  test "Trivy failures propagate and stop subsequent work":
    for stage in ["template", "summary", "json", "convert-template", "convert-table"]:
      putEnv("TRIVY_TEST_FAIL", stage)
      writeFile(sandbox / "calls", "")
      let target = if stage.startsWith("convert"): "a,b" else: "a"
      let res = invoke(@["image", target, sandbox / "fail.html"])
      check res.exitCode == 7
      check "##teamcity[" notin res.output
      check scratchEmpty()
  test "multi-target scan failure stops before conversion":
    putEnv("TRIVY_TEST_FAIL", "json")
    check invoke(@["image", "a,b", sandbox / "fail.html"]).exitCode == 7
    check calls().len == 1
    check scratchEmpty()
  test "invalid JSON fails without statistics and cleans temporary files":
    putEnv("TRIVY_TEST_INVALID", "1")
    let res = invoke(@["image", "a,b", sandbox / "invalid.html"])
    check res.exitCode != 0
    check "##teamcity[" notin res.output
    check scratchEmpty()

putEnv("PATH", oldPath)
if oldTmp.len == 0: delEnv("TMPDIR")
else: putEnv("TMPDIR", oldTmp)
for key in ["TRIVY_TEST_LOG", "TRIVY_TEST_MERGED", "TRIVY_TEST_FAIL", "TRIVY_TEST_INVALID"]:
  delEnv(key)
removeDir(sandbox)
