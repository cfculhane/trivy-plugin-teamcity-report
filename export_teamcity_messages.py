#!/usr/bin/env python3

import json
import sys
from enum import Enum
from pprint import pformat
from time import time, localtime, strftime
from typing import Dict

_quote = {"'": "|'", "|": "||", "\n": "|n", "\r": "|r", '[': '|[', ']': '|]'}


def escape_value(value):
    return "".join(_quote.get(x, x) for x in value)


class Severity(str, Enum):
    UNKNOWN = "UNKNOWN"
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


def teamcity_message(messageName: str, **properties):
    current_time = time()
    (current_time_int, current_time_fraction) = divmod(current_time, 1)
    current_time_struct = localtime(current_time_int)

    timestamp = strftime("%Y-%m-%dT%H:%M:%S.", current_time_struct) + "%03d" % (int(current_time_fraction * 1000))
    message = ("##teamcity[%s timestamp='%s'" % (messageName, timestamp))

    for k in sorted(properties.keys()):
        value = properties[k]
        if value is None:
            continue

        message += (" %s='%s'" % (k, escape_value(value)))

    message += ("]\n")
    print(message)


def process_output(results: Dict) -> None:
    all_vulns = []
    all_misconfigs = []
    vuln_scan = False
    config_scan = False
    for result in results["Results"]:
        if result.get("Class") == "config":
            config_scan = True  # Even without misconfigs this this will be present
            if result.get("Misconfigurations"):
                all_misconfigs.extend(result.get("Misconfigurations", []))
        else:
            vuln_scan = True  # We assume there will be at least one vuln, even a low one, present to use as a test
            if result.get("Vulnerabilities") is None:
                print(f"Warning - could not find any vulns, check this is accurate! Result was: \n{pformat(result)}")
            all_vulns.extend(result.get("Vulnerabilities", []))

    if vuln_scan:
        for severity in Severity:
            vuln_count = len([v for v in all_vulns if v["Severity"] == severity])
            print(f"##teamcity[buildStatisticValue key='VULNERABLITY_COUNT_{severity}' value='{vuln_count}']")

    if config_scan:
        for severity in Severity:
            misconfig_count = len([v for v in all_misconfigs if v["Severity"] == severity])
            print(f"##teamcity[buildStatisticValue key='MISCONFIGURATION_COUNT_{severity}' value='{misconfig_count}']")


if __name__ == '__main__':
    trivy_output = json.loads(sys.stdin.read())
    if trivy_output.get("Results") is None or len(trivy_output["Results"]) == 0:
        print("Could not find any results, check logs for details.")
        exit(0)
    else:
        process_output(trivy_output)
