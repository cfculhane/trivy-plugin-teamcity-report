import std/[json, os, strutils]
let args = commandLineParams()
let log = open(getEnv("TRIVY_TEST_LOG"), fmAppend)
log.writeLine($(%args))
log.close()
proc option(name: string): string =
  let index = args.find(name)
  if index >= 0 and index + 1 < args.len: args[index + 1] else: ""
let format = option("--format")
let stage = if args[0] == "convert": "convert-" & format
            elif format == "": "summary"
            else: format
if getEnv("TRIVY_TEST_FAIL") == stage:
  stderr.writeLine("simulated Trivy failure")
  quit(7)
if args[0] == "convert":
  let doc = parseFile(args[^1])
  writeFile(getEnv("TRIVY_TEST_MERGED"), $doc)
if format == "template":
  let templatePath = option("--template")
  doAssert templatePath.startsWith("@")
  doAssert readFile(templatePath[1..^1]).contains("<html")
  writeFile(option("--output"), "<html>test report</html>")
elif format == "json":
  let data = if getEnv("TRIVY_TEST_INVALID") == "1": "broken json"
             else: $(%*{"SchemaVersion": 2, "ArtifactName": args[1],
               "Results": [{"Target": args[1], "Class": "os-pkgs",
                 "Vulnerabilities": [{"Severity": "HIGH"}]}]})
  writeFile(option("--output"), data)
