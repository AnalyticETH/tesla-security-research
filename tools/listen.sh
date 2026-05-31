#!/bin/bash
# Based on listen-for-code.sh by Lunars
# https://github.com/Lunars/tesla/blob/master/src/scripts/everyBoot/listen-for-code.sh

#commands are listed below. serviceplus,service,ap, etc.
# enter ip address and port for backshell <0-255>.<0-255>.<0-255>.<0-255>:<0-65535> - any port below 1024 is restricted to be used by non-root users.
# /GUI_tdsMode [value] - sets something. Start it with the slash, value is optional and set to true by default.
# ?GUI_tdsMode - queries the variable. Output could be unreliable on this stage

pattern=AccessPopup
sdv="sh /var/log/wpa_supplicant/sdv"
lv="sh /var/log/wpa_supplicant/lv"

# disable speed restriction
sh /var/log/wpa_supplicant/sdv GUI_disableAutosteerRestrictions true

if ps ax | grep $0 | grep -v $$ | grep bash | grep -v grep; then
  echo "The script is already running."
  exit 1
fi

# AP report button
sh /var/log/wpa_supplicant/sdv FEATURE_autopilotSnapshots true

#Enable undertake assist every time
sh /var/log/wpa_supplicant/sdv GUI_undertakeAssistEnable true

#Allow autopark in more places
sh /var/log/wpa_supplicant/sdv GUI_autoparkAllowVirtualCurb true
sh /var/log/wpa_supplicant/sdv GUI_autoparkAllowPOC true

while true; do
  if inotifywait -q -q -e modify /var/log/qtcar/current; then
    msg=$(tail -n 100 /var/log/qtcar/current | grep "access code" | tail -n 1)

    if [[ "$msg" != "$last_message" ]] && [[ $msg == *$pattern* ]]; then
      command=$(echo "$msg" | awk -F'entered: ' '{ print $2 }')
      last_message=$msg
      res="NoNe"

      echo "Processing command $command"

      case $command in
      "serviceplus ")
        res=$($sdv GUI_serviceModePlus true && $sdv GUI_serviceModeManagedSettingOverride true)
        ;;
      "service ")
        res=$($sdv GUI_serviceMode true)
        ;;
      "go ")
      res=$($sdv GUI_disableAutosteerRestrictions true && $sdv GUI_undertakeAssistEnable true)
        ;;
      "ap ")
      res=$($sdv GUI_disableAutosteerRestrictions true)
        ;;
      "matt ")
        res=$($sdv GUI_developerMode true && $sdv GUI_diagnosticMode true && $sdv GUI_tdsMode true)
        ;;
      "dev ")
        res=$($sdv GUI_developerMode true)
        ;;
      "diag ")
        res=$($sdv GUI_diagnosticMode true)
        ;;
      "tds ")
        res=$($sdv GUI_tdsMode true)
        ;;
      "debug ")
        res=$($sdv GUI_autopilotClusterDebug true && $sdv GUI_dasDebugOn true && $sdv GUI_dasDevMode true && $sdv GUI_dasDeveloper true && $sdv GUI_isDevelopmentCar true)
        ;;
      "reboot ")
        res=$(sh /var/log/wpa_supplicant/reboot.sh)
        ;;
      "hand ")
        res=$(sh /usr/local/bin/emit-firmware-handshake)
        ;;
      "check ")
        res=$(curl -X POST -H "User-Agent: ice-updater/4fc0b571da2e3284" -v http://firmware.vn.teslamotors.com:4567/vehicles/$(cat /var/etc/vin)/check_for_firmware_update)
        ;;
      "snap ")
        res=$($sdv FEATURE_autopilotSnapshots true)
        ;;
      "das ")
        res=$($sdv DASUI_drivableSpace true && $sdv DASUI_visualizeCityStreetsString true && $sdv DASUI_visualizeControllerString true && $sdv DASUI_visualizeDriveOnNavString true && $sdv DASUI_visualizeMapString true && $sdv DASUI_visualizePlannerString true && $sdv DASUI_visualizeStateMachineString true && $sdv DASUI_visualizeVisionString true)
        ;; #  $sdv DASUI_grid true && $sdv DASUI_capture true && $sdv DASUI_occupancy true && $sdv DASUI_topDown true &&
      "fsd ")
        res=$($sdv GUI_expandFsdVisualizationEnable true && $sdv FEATURE_fullSelfDriving true && $sdv GUI_fsdControlEnabled true && $sdv FEATURE_hasFullSelfDrivingNavMaps true)
        ;;
      "full ")
        res=$($sdv GUI_expandFsdVisualizationEnable true && $sdv GUI_controlsVizMode true && $sdv GUI_cityStreetsActive true && $sdv GUI_alwaysShowSCWVisualization true && $sdv GUI_showMultipleLeadVehicles true && $sdv GUI_showLaneGraph true && $sdv GUI_enableFSDFunctions true && $sdv GUI_fsdControlEnabled true)
        ;;
      "feat ")
        res=$($sdv FEATURE_enableJunctionView true && $sdv FEATURE_fullSelfDriving true && $sdv FEATURE_hasFullSelfDrivingNavMaps true && $sdv FEATURE_dasLaneSupportSystemEnabled true && $sdv FEATURE_enableFSDAutoNav true && $sdv FEATURE_useWayLaneProb true && $sdv FEATURE_teslaAutopark true && $sdv FEATURE_subgraphLocalizerMode true && $sdv FEATURE_blindspotWarningEnabled true && $sdv FEATURE_dasLaneSupportSystemEnabled true && $sdv FEATURE_useWayLaneProb true && $sdv FEATURE_wave1 true && $sdv FEATURE_allowDashcamOverride true)
        ;;
      "park ")
        res=$($sdv GUI_useAutopark2 true $sdv GUI_easySelfParkEnabled true && $sdv GUI_autoparkAllowCrossPark true && $sdv DAS_autoparkReady true && $sdv GUI_autoparkAllowPOC true && $sdv GUI_autoparkAllowVirtualCurb true && $sdv GUI_selfParkAllowNarrowGarages true)
        ;;
      "nav ")
        res=$($sdv FEATURE_cautionLightsControlEnabled true && $sdv FEATURE_enableAlternativeRoutes true && $sdv FEATURE_enableRerouteButtons true && $sdv FEATURE_enableFSDAutoNav)
        ;;
      "hzn ")
        res=$($sdv HZN_currentBranchIsSideCollisionAssistEnabled true)
        ;;
      "ping ")
        res="pong!"
        ;;
      "ip ")
        res=$(ip addr show)
        ;;
      "uname ")
        res=$(uname -a)
        ;;
      " help")
        res=$(grep -o '" .*")' /var/log/wpa_supplicant/listen.sh | tr -d '") ') # Get all commands from this file
        res="${res//$'\n'/ }"        # Replace newlines
        ;;
      " ")
        ;;
      *)
        if [[ $command =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\:[0-9]+\ $ ]]; then # backshell
          socat tcp4:$command exec:/bin/sh,pty,stderr,setsid,sigint,sane &
        elif [[ $command == \/* ]]; then
          res=$($sdv ${command:1})   # note no string sanitizing here to allow arbitruary command calls :)
        elif [[ $command == \?* ]]; then
          res=$($lv ${command:1})   # note no string sanitizing here to allow arbitruary command calls :)
        fi
        ;;
      esac
      if [ "$res" != "NoNe" ]; then
        msg_txt="Running $command returned: $res"
        curl -G -m 60 -f -s http://cid:7654/pop_question -d responses=Ok --data-urlencode message="$msg_txt" 2> /dev/null &
      fi
    fi
  fi
done
