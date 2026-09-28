## Trivy report generation and TeamCity statistics in one executable.
import std/[json, os, osproc, strutils, tempfiles]

const
  htmlTemplate = staticRead("../html.tpl")
  severities* = ["UNKNOWN", "LOW", "MEDIUM", "HIGH", "CRITICAL"]
  usage = """Usage: trivy teamcity-report OPERATION TARGET OUTPUTFILE [TRIVYPARAMS]
Targets may be comma-separated. Use -h or --help to show this message.
Examples:
  trivy teamcity-report image nginx:1.27,redis:7 output.html
  trivy teamcity-report fs /path/to/dir output.html --scanners vuln,config
"""

type TrivyError* = object of CatchableError
  exitCode*: int

proc resultsArray(doc: JsonNode): JsonNode =
  if doc.kind != JObject:
    raise newException(ValueError, "Trivy report must be a JSON object")
  result = doc{"Results"}
  if result.isNil or result.kind == JNull:
    return newJArray()
  if result.kind != JArray:
    raise newException(ValueError, "Trivy Results must be an array")

proc mergeReports*(docs: openArray[JsonNode]): JsonNode =
  result = if docs.len == 0: newJObject() else: docs[0].copy()
  discard resultsArray(result)
  result["Results"] = newJArray()
  for doc in docs:
    for item in resultsArray(doc):
      result["Results"].add(item.copy())

proc statisticMessages*(doc: JsonNode): seq[string] =
  var counts: array[2, array[severities.len, int]]
  var seen: array[2, bool]
  for item in resultsArray(doc):
    if item.kind != JObject:
      raise newException(ValueError, "Trivy result must be an object")
    let category = if item{"Class"}.getStr() == "config": 1 else: 0
    seen[category] = true
    let findings = item{if category == 1: "Misconfigurations" else: "Vulnerabilities"}
    if findings.isNil or findings.kind == JNull:
      continue
    if findings.kind != JArray:
      raise newException(ValueError, "Trivy findings must be an array")
    for finding in findings:
      for index, severity in severities:
        if finding{"Severity"}.getStr() == severity:
          inc counts[category][index]
  for category, prefix in ["VULNERABILITY", "MISCONFIGURATION"]:
    if seen[category]:
      for index, severity in severities:
        result.add("##teamcity[buildStatisticValue key='" & prefix &
          "_COUNT_" & severity & "' value='" & $counts[category][index] & "']")

proc runTrivy(args: seq[string]) =
  let process = startProcess("trivy", args = args,
    options = {poUsePath, poParentStreams})
  defer: process.close()
  let code = process.waitForExit()
  if code != 0:
    var error = newException(TrivyError, "Trivy failed with exit code " & $code)
    error.exitCode = code
    raise error

proc run*(args: seq[string]): int =
  if args.len == 0 or args[0] in ["-h", "--help"]:
    stdout.write(usage)
    return 0
  if args.len < 3 or args[0].len == 0 or args[2].len == 0:
    stderr.writeLine("Specify OPERATION TARGET OUTPUTFILE\n" & usage)
    return 1
  var targets: seq[string]
  for target in args[1].split(','):
    if target.len > 0: targets.add(target)
  if targets.len == 0:
    stderr.writeLine("No valid targets after parsing CSV")
    return 1
  let params = if args.len > 3: args[3..^1] else: @[]
  let workdir = createTempDir("trivy-teamcity-", "")
  defer: removeDir(workdir)
  let templatePath = workdir / "html.tpl"
  writeFile(templatePath, htmlTemplate)
  let multiple = ',' in args[1]
  if not multiple:
    echo "Scanning and exporting HTML report to '", args[2], "'"
    runTrivy(@[args[0]] & params & @["--format", "template", "--template",
      "@" & templatePath, "--output", args[2], targets[0]])
    echo "Printing summary:"
    runTrivy(@[args[0], "--quiet"] & params & @[targets[0]])
  var docs: seq[JsonNode]
  for index, target in targets:
    echo "Scanning ", target
    let jsonPath = workdir / ($index & ".json")
    runTrivy(@[args[0], target] & params & @["--quiet", "--format", "json",
      "--severity", severities.join(","), "--output", jsonPath])
    docs.add(parseFile(jsonPath))
  let merged = mergeReports(docs)
  if multiple:
    let mergedPath = workdir / "merged.json"
    writeFile(mergedPath, $merged)
    echo "Exporting HTML report to '", args[2], "'"
    runTrivy(@["convert", "--format", "template", "--template",
      "@" & templatePath, "--output", args[2], mergedPath])
    echo "Printing summary:"
    runTrivy(@["convert", "--format", "table", mergedPath])
  echo "Emitting teamcity messages:"
  let messages = statisticMessages(merged)
  if messages.len == 0:
    echo "Could not find any results, check logs for details."
  for message in messages: echo message

when isMainModule:
  try:
    quit(run(commandLineParams()))
  except TrivyError as error:
    stderr.writeLine(error.msg)
    quit(error.exitCode)
  except CatchableError as error:
    stderr.writeLine("teamcity-report: " & error.msg)
    quit(1)
