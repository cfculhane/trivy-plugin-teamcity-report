#!/usr/bin/env python3

import json
import sys
from enum import Enum
from time import time, localtime, strftime
from typing import Dict

_quote = {"'": "|'", "|": "||", "\n": "|n", "\r": "|r", '[': '|[', ']': '|]'}


def escape_value(value):
    return "".join(_quote.get(x, x) for x in value)


class VulnSeverity(str, Enum):
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


def process_vulnerabilities(results: Dict) -> None:
    all_vulns = []
    for vulns in results["Results"]:
        all_vulns.extend(vulns["Vulnerabilities"])

    for vuln_severity in VulnSeverity:
        vuln_count = len([v for v in all_vulns if v["Severity"] == vuln_severity])
        print(f"Number of {vuln_severity} vulnerabilities = {vuln_count}")
        print(f"##teamcity[buildStatisticValue key='VULNERABLITY_COUNT_{vuln_severity}' value='{vuln_count}']")


if __name__ == '__main__':
    trivy_output = json.loads(sys.stdin.read())

    # TODO add report type detection
    process_vulnerabilities(trivy_output)
