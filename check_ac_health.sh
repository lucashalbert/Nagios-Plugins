#!/bin/bash
print_version() {
    cat <<EOF
####################################################################################
#
# Author:       Lucas Halbert <https://www.lhalbert.xyz>
# Date:         12/17/2015
# Last Edited:  11/30/2016
# Version:      2016.11.30
# Description:  Checks the status of air conditioning units.
#  License:     BSD 3-Clause License
#
#  Copyright (c) 2016, Lucas Halbert
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
#  * Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
#  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
#  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
#  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
####################################################################################
EOF
}

print_changelog() {
    cat <<EOF
####################################################################################
#
#  Revisions:   11/30/2016  Fix argument parsing and update usage.
#
#               11/29/2016  Build humidity thresholds into script. Fix output 
#                           format to allow for proper notifications.
#
#               12/17/2015  Initial draft of script modeled after PHP AC script.
#
####################################################################################
EOF
}

print_usage() {
    cat <<EOF
Usage: $0   [-vVhH] [-U URL] [-u user] [-p pass]
            [-w|--wc cold aisle warn] [-c|--cc cold aisle crit]
            [-W|--wh aisle warn] [-C|--ch hot aisle crit]
            [-a|--wa avg warn] [-A|--ca avg crit] [--wl low humid warn]
            [--cl low humid crit] [--wu high humid warn] [--cu high humid crit]
            [-t <timeout>]
EOF

}
print_help() {
    cat <<EOF
NAME
       $0 - checks the temperature of air conditioner units and returns the status for nagios

SYNOPSIS
       $0 [-vVhH] [-U URL] [-u user] [-p pass]
            [-w|--wc cold aisle warn] [-c|--cc cold aisle crit]
            [-W|--wh aisle warn] [-C|--ch hot aisle crit]
            [-a|--wa avg warn] [-A|--ca avg crit] [--wl low humid warn]
            [--cl low humid crit] [--wu high humid warn] [--cu high humid crit]
            [-t <timeout>]

DESCRIPTION
       $0 checks the temperature of air conditioner units and returns the status for nagios

OPTIONS
       -U URL
              URL of air conditioner thermostat

       -u username
              Username to authenticate with

       -p password
              Password to authenticate with

       -w|--wc temperature
              Cold aisle warning temperature

       -c|--cc temperature
              Cold aisle critical temperature

       -W|--wh temperature
              Hot aisle warning temperature

       -C|--ch temperature
              Hot aisle critical temperature

       -a|--wa temperature
              Hot and cold aisle average warning temperature

       -A|--ca temperature
              Hot and cold aisle average critical temperature

       --wl humidty(in percent)
              Low humidity warning in percent

       --cl humidty(in percent)
              Low humidity critical in percent

       --wu humidty(in percent)
              High(upper) humidity warning in percent

       --cu humidty(in percent)
              High(upper) humidity critical in percent

       -t|--timeout seconds
              Timeout in seconds before plugin fails

       -v|-vv
              Increase verbosity

       -h
              Print usage

       -H|--help
              Print detailed usage (this page) 

       -V
              Print version details and changelog
EOF
}

TIMEOUT=5
STATE=""
STATE_OK=0
STATE_CRITICAL=2
STATE_WARNING=1
STATE_UNKNOWN=3
VERBOSE=0
TOTAL_SIZE=0
POSTOPTIONS=('OID1' 'OID2.5.1' 'OID4.3.2.1' 'OID4.3.2.2' 'OID4.1.13' 'OID4.1.14' 'OID4.1.1' 'OID4.1.2' 'OID4.1.3' 'OID4.1.4' 'OID4.1.5' 'OID4.1.6' 'OID1.1' 'OID1.2' 'OID2.7.1')
#2.5.1:      local time
#4.3.2.1     local temperature
#4.3.2.2:    zone humidity
#4.1.13:     zone temperature
#4.1.6:      cool setting
#1.1:        Firmware Version
#1.2:        hostname
#2.7.1:      model#
#4.1.1:      HvacMode
#4.1.2:      HvacState
#4.1.3:      FanMode
#4.1.4:      FanState
#4.1.5:      SetbackHeat
#4.1.6:      SetbackCool

declare -A RESULT
declare -a PERFDATA=("|")

gatherOutput() {
	temp=$(curl --anyauth --connect-timeout ${TIMEOUT} -s -d \"$(echo ${POSTOPTIONS[*]} | sed 's/\s/\=\&/g')\" -u ${USER}:${PASS} ${URL})
    if [[ "$?" -eq 28 ]]; then
        echo "UNKNOWN: Connection timed out"
        exit $STATE_UNKNOWN
    fi
    curlOutput="$temp"
	
	# Parse Data and store in an associative array
	saveIFS=$IFS
	IFS='=&'
	temp=($temp)
	IFS=$saveIFS
    if [[ ! ${#temp[@]} -gt 1 ]]; then
        echo "CRITICAL: the data could not be collected from ${URL}"
        exit $STATE_CRITICAL
    fi
	for ((i=0; i<${#temp[@]}; i+=2)); do
	    RESULT[${temp[i]}]=${temp[i+1]}
	done
}

compileData() {
#thermHvacModeOID = "4.1.1": {"Off":1},{"Heat":2},{"Cool":3},{"Auto":4},{"Em Ht":5}],"default":4
#thermHvacStateOID = "4.1.2": {"Initializing":1},{"Off":2},{"Heat":3},{"Heat2":4},{"Heat3":5},{"Heat4":6},{"Cool":7},{"Cool2":8},{"Cool3":9},{"Cool4":10},{"Aux Ht":11},{"Aux Ht2":12},{"Em Ht":13},{"Fault":14}],"default":1
#thermFanModeOID = "4.1.3": {"Auto":1},{"On":2},{"Scheduled":3}],"default":1
#thermFanStateOID = "4.1.4": {"Init":0},{"Off":1},{"On":2}],"default":1
#thermSetbackHeatOID = "4.1.5": range":{"inc":10,"high":1100,"low":400},"default":650}
#thermSetbackCoolOID = "4.1.6": range":{"inc":10,"high":1100,"low":400},"default":780}
#thermAverageTempOID = "4.1.13": DECIDEGREE","range":{},"default":-2147483647}
#thermRelativeHumidityOID = "4.1.14": INTEGER","range":{"high":100,"low":0},"default":-2147483647}"
	
	HOTAISLE=$(echo ${RESULT['OID4.3.2.1']} | sed 's/.\{2\}/&./')
	COLDAISLE=$(echo ${RESULT['OID4.1.13']} | sed 's/.\{2\}/&./')
    AVERAGETEMP=$(echo -e "${COLDAISLE}\n${HOTAISLE}" | awk '{s+=$1}END{print s/NR}')
    HUMIDITY=$(echo -e "${RESULT['OID4.3.2.2']}") 
	SETTEMP=$(echo ${RESULT['OID4.1.6']} | sed 's/.\{2\}/&./')
    case ${RESULT['OID4.1.2']} in
        1) HVACSTATE="device reset before operation" ;;
        2) HVACSTATE="Not operating" ;;
        3) HVACSTATE="Heating first stage" ;;
        4) HVACSTATE="Heating first and second stage" ;;
        5) HVACSTATE="Auxillary heat (Heat Pump Only)" ;;
        6) HVACSTATE="Cooling first stage" ;;
        7) HVACSTATE="Cooling, first and second stage" ;;
        8) HVACSTATE="Waiting for compressor delay to timeout" ;;
        9) HVACSTATE="Intermediate state, returning relays to inactive" ;;
    esac
    
    # Check Temperature Thresholds
    if [[ "$COLDCRIT" && "$COLDWARN" ]]; then
        PERFDATA+=($(echo "COLDAISLE=${COLDAISLE}F;${COLDWARN};${COLDCRIT};0;120"))
        # Check Cold Aisle temps
        if [ `echo $COLDAISLE $COLDCRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s" "${STATE} COLDAISLE CRITICAL - ${COLDAISLE}F,")
        elif [ `echo $COLDAISLE $COLDWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s" "${STATE} COLDAISLE WARNING - ${COLDAISLE}F,")
        else
            STATE=$(printf "%s" "${STATE} COLDAISLE OK - ${COLDAISLE}F,")
        fi
    else
        PERFDATA+=($(echo "COLDAISLE=${COLDAISLE}F;${COLDWARN};${COLDCRIT};0;120"))
    fi
    if [[ "$HOTCRIT" && "$HOTWARN" ]]; then
        PERFDATA+=($(echo "HOTAISLE=${HOTAISLE}F;${HOTWARN};${HOTCRIT};0;120"))
        # Check Cold Aisle temps
        if [ `echo $HOTAISLE $HOTCRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s" "${STATE} HOTAISLE CRITICAL - ${HOTAISLE}F,")
        elif [ `echo $HOTAISLE $HOTWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s" "${STATE} HOTAISLE WARNING - ${HOTAISLE}F,")
        else
            STATE=$(printf "%s" "${STATE} HOTAISLE OK - ${HOTAISLE}F,")
        fi
    else
        PERFDATA+=($(echo "HOTAISLE=${HOTAISLE}F;${HOTWARN};${HOTCRIT};0;120"))
    fi
    if [[ "$AVECRIT" && "$AVEWARN" ]]; then
        PERFDATA+=($(echo "AVERAGETEMP=${AVERAGETEMP}F;${AVEWARN};${AVECRIT};0;120"))
        # Check Cold Aisle temps
        if [ `echo $AVERAGETEMP $AVECRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s" "${STATE} AVERAGE CRITICAL - ${AVERAGETEMP}F,")
        elif [ `echo $AVERAGETEMP $AVEWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s" "${STATE} AVERAGE WARNING - ${AVERAGETEMP}F,")
        else
            STATE=$(printf "%s" "${STATE} AVERAGE OK - ${AVERAGETEMP}F,")
        fi
    else
        PERFDATA+=($(echo "AVERAGETEMP=${AVERAGETEMP}F;${AVEWARN};${AVECRIT};0;120"))
    fi

    
    # Check Humidity Thresholds
    if [[ "$HUMIDITY" -lt 50 ]]; then
	    if [[ "$LOWCRIT" && "$LOWWARN" ]]; then
	        PERFDATA+=($(echo "HUMIDITY=${HUMIDITY}%;$LOWWARN;${LOWCRIT};0;100"))
	        # Check Cold Aisle temps
	        if [ `echo $HUMIDITY $LOWCRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "true" ]; then
	            STATE=$(printf "%s" "${STATE} LOW HUMIDITY CRITICAL - ${HUMIDITY}%,")
	        elif [ `echo $HUMIDITY $LOWWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "true" ]; then
	            STATE=$(printf "%s" "${STATE} LOW HUMIDITY WARNING - ${HUMIDITY}%,")
	        else
	            STATE=$(printf "%s" "${STATE} HUMIDITY OK - ${HUMIDITY}%,")
	        fi
	    else
	        PERFDATA+=($(echo "HUMIDITY=${$HUMIDITY}F;${LOWWARN};${LOWCRIT};0;120"))
	    fi
    elif [[ "$HUMIDITY" -ge 50 ]]; then
	    if [[ "$UPCRIT" && "$UPWARN" ]]; then
	        PERFDATA+=($(echo "HUMIDITY=${HUMIDITY}%;$UPWARN;${UPCRIT};0;100"))
	        # Check Cold Aisle temps
	        if [ `echo $HUMIDITY $UPCRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
	            STATE=$(printf "%s" "${STATE} HIGH HUMIDITY CRITICAL - ${HUMIDITY}%,")
	        elif [ `echo $HUMIDITY $UPWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
	            STATE=$(printf "%s" "${STATE} HIGH HUMIDITY WARNING - ${HUMIDITY}%,")
	        else
	            STATE=$(printf "%s" "${STATE} HUMIDITY OK - ${HUMIDITY}%,")
	        fi
	    else
	        PERFDATA+=($(echo "HUMIDITY=${$HUMIDITY}F;${UPWARN};${UPCRIT};0;120"))
	    fi
    fi

    STATE=$(printf "%s" "${STATE} HVAC STATE - ${HVACSTATE}")
    if [[ "${RESULT['OID4.1.2']}" -eq 2 || "${RESULT['OID4.1.2']}" -eq 8 ]]; then
        PERFDATA+=($(echo "HVACSTATE=0;0;0;0;1"))
    elif [[ "${RESULT['OID4.1.2']}" -eq 6 || "${RESULT['OID4.1.2']}" -eq 7 ]]; then
        PERFDATA+=($(echo "HVACSTATE=1;0;0;0;1"))
    fi
}

printVerbose() {
	# Print Verbose Info
	if [ "$VERBOSE" -gt 0 ]; then
	    echo "#---- Debug Info ----#"
	    if [ "$VERBOSE" -gt 1 ]; then
	        count=0
	        for i in "${POSTOPTIONS[@]}"; do
	            echo ${POSTOPTIONS[$count]}: ${RESULT[$i]}
	            ((count++))
            done
            if [ "$VERBOSE" -gt 2 ]; then
                echo AC URL: $URL
                echo AC User: $USER
                echo AC Pass: $PASS
            fi
        fi
	    echo COLD Warning Temp: ${COLDWARN}F
	    echo COLD Critical Temp: ${COLDCRIT}F
	    echo HOT Warning Temp: ${HOTWARN}F
	    echo HOT Critical Temp: ${HOTCRIT}F
	    echo Low Humidity Warning: ${LOWWARN}%
	    echo Low Humidity Critical: ${LOWCRIT}%
	    echo High Humidity Warning: ${UPWARN}%
	    echo High Humidity Critical: ${UPCRIT}%
	    echo HVAC SET Temp: ${SETTEMP}F
	    echo COLDAISLE Temp: ${COLDAISLE}F
	    echo HOTAISLE Temp: ${HOTAISLE}F
	    echo Average Temp: ${AVERAGETEMP}F
	    echo HVAC STATE: ${HVACSTATE}
	    echo -e "#---- Debug Info ----#\n"
	    echo -e "#---- Standard Output ----#"
	fi
}

printStatus() {
	# Fix STATE formatting
	STATE=$(echo -e "${STATE}\n${PERFDATA[*]}")
	STATE=$(echo -e "$STATE" | sed '/^$/d')
	# Determine State
	if [[ $(echo "$STATE" | grep "CRITICAL" | wc -l) -gt 0 ]]; then
	    echo "$STATE"
	    exit $STATE_CRITICAL
	elif [[ $(echo "$STATE" | grep "WARNING" | wc -l) -gt 0 ]]; then
	    echo "$STATE"
	    exit $STATE_WARNING
	elif [[ $(echo "$STATE" | egrep "(CRITICAL|WARNING)" | wc -l) -eq 0 ]]; then
	    echo "$STATE"
	    exit $STATE_OK
	else
	    echo "$STATE"
	    exit $STATE_UNKNOWN
	fi
}

if [ ! "$#" -gt 0 ]; then
    echo "This command requires arguments"
    print_usage
    exit $STATE_UNKNOWN
fi

OPTS=$(getopt -o a:A:U:u:p:w:c:W:C:t:vVhH --long help,wa:,ca:,wc:,cc:,wh:,ch:,wu:,cu:,wl:,cl: -- "$@")
if [ $? != 0 ]; then
    echo "Failed parsing options." >&2;
    exit $STATE_UNKNOWN
fi

eval set -- "$OPTS"
while true; do
    case "$1" in
      -a|--wa)
        AVEWARN=$2; shift 2 ;;
      -A|--ca)
        AVECRIT=$2; shift 2 ;;
      -U)
        URL=$2; shift 2 ;;
      -u)
        USER=$2; shift 2 ;;
      -p)
        PASS=$2; shift 2 ;;
      -w|--wc)
        COLDWARN=$2; shift 2 ;;
      -c|--cc)
        COLDCRIT=$2; shift 2 ;;
      -W|--wh)
        HOTWARN=$2; shift 2 ;;
      -C|--ch)
        HOTCRIT=$2; shift 2 ;;
      -t)
        TIMEOUT=$2; shift 2 ;;
      --wl)
        LOWWARN=$2; shift 2 ;;
      --cl)
        LOWCRIT=$2; shift 2 ;;
      --wu)
        UPWARN=$2; shift 2 ;;
      --cu)
        UPCRIT=$2; shift 2 ;;
      -v)
        VERBOSE=$((VERBOSE+1)); shift ;;
      -V)
        print_version
        print_changelog
        exit 0
        ;;
      -h)
        print_usage
        exit $STATE_UNKNOWN
        ;;
      -H|--help)
        print_help
        exit $STAT_UNKNOWN
        ;;
      --)
        shift; break ;;
      \?)
        echo "Invalid option: $OPTARG"
        print_usage
        exit $STATE_UNKNOWN
        ;;
      :)
        echo "Option -$OPTARG requires an argument"
        exit $STATE_UNKNOWN
        ;;
      *)
        break
        echo "Syntax Error"
        print_help
        exit $STATE_UNKNOWN
        ;;
    esac
done

gatherOutput
compileData
printVerbose
printStatus
