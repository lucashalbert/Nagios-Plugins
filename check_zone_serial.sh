#!/bin/bash
print_version() {
    cat <<EOF
####################################################################################
#
# Author:       Lucas Halbert <https://www.lhalbert.xyz>
# Date:         11/23/2016
# Last Edited:  02/28/2019
# Version:      2019.02.28
# Description:  Checks DNS zone serial to ensure it is not out of date
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
#  Revisions:   2019.02.28  Fix usage and help
#
#               2016.11.23  Initial draft
#
####################################################################################
EOF
}

print_usage() {
    cat <<EOF

$0 Checks DNS zone serial to ensure it is not out of date

Usage: $0 -S <DNS server> -Z <zone> -W <days> -C <days> [-v|-vv] [-V] [-h] [-H]

EOF
}

print_help() {
    cat <<EOF
NAME
       $0 - Checks DNS zone serial to ensure it is not out of date

SYNOPSIS
       $0 -S <DNS server> -Z <zone> -W <days> -C <days> [-v|-vv] [-V] [-h] [-H]

DESCRIPTION
       $0 - Checks the RRSIG expiration date of a DNSSEC signed DNS zone

OPTIONS
       -S|--server <hostname|IP>
              Server hostname to query

       -Z|--zone <zone>
              Zone to query

       -W|--warn <days>
              Zone serial expiration warning in days

       -C|--crit <days>
              Zone serial expiration critical in days

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

STATE=""
STATE_OK=0
STATE_CRITICAL=2
STATE_WARNING=1
STATE_UNKNOWN=3
VERBOSE=0
TOTAL_SIZE=0
declare -a PERFDATA=("|")

gatherOutput() {
    zoneSerial=$(dig SOA @${SERVER} ${ZONE} | grep "^${ZONE}" | grep SOA | awk '{print $7}')
	if [ -z "${zoneSerial}" ]; then
	    echo "CRITICAL: The Zone ${ZONE} does not exist"
	    echo "$output"
	    exit $STATE_CRITICAL
	fi
}

compileData() {
    nowSeconds=$(date +'%s')
    zoneSeconds=$(date -d "${zoneSerial::-2}" '+%s')
    daysOld=$(( (${nowSeconds}-${zoneSeconds})/(60*60*24) ))
	if [[ "$CRIT" && "$WARN" ]]; then
        PERFDATA+=($(echo "${ZONE}=${daysOld}days;${WARN};${CRIT};0;$((${CRIT} + ${daysOld}))"))
	    # Check zone age
        if [ `echo ${daysOld} ${CRIT} |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(echo "ZONE CRITICAL: ${ZONE} zone is ${daysOld} days old")
        elif [ `echo ${daysOld} $WARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(echo "ZONE WARNING: ${ZONE} zone is ${daysOld} days old")
	    else
            STATE=$(echo "ZONE OK: ${ZONE} zone is ${daysOld} days old")
	    fi
    fi
}
	
printVerbose() {
	# Print Verbose Info
	if [ "$VERBOSE" -gt 0 ]; then
	    echo "#---- Debug Info ----#"
        if [ "$VERBOSE" -gt 1 ]; then
            echo "Warn Threshold: ${WARN} days"
            echo "Crit Threshold: ${CRIT} days"
	    fi
        echo "Now $(date +'%Y%m%d00')"
        echo "Zone Serial: ${zoneSerial}"
        echo "NowSeconds: ${nowSeconds}"
        echo "ZoneSeconds: ${zoneSeconds}"
        echo "DaysOld: ${daysOld}"
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

while getopts ":S:Z:W:C:vVhH" opt; do
    case $opt in
      S)
        SERVER=$OPTARG
        ;;
      Z)
        ZONE=$OPTARG
        ;;
      W)
        WARN=$OPTARG
        ;;
      C)
        CRIT=$OPTARG
        ;;
      v)
        VERBOSE=$((VERBOSE+1))
        ;;
      V)
        print_version
        print_changelog
        exit $STATE_OK
        ;;
      h)
        print_usage
        exit $STATE_OK
        ;;
      H|--help)
        print_help
        exit $STATE_OK
        ;;
      \?)
        echo "Invalid option: $OPTARG"
        print_usage
        exit $STATE_UNKNOWN
        ;;
      :)
        echo "Option -$OPTARG requires an argument"
        exit $STATE_UNKNOWN
        ;;
    esac
done

if [ -z "$SERVER" -o -z "$ZONE" -o -z "$WARN" -o -z "$CRIT" ]; then
    if [ -z "${SERVER}" ]; then
        echo "UNKNOWN: Server was not specified"
    fi
    if [ -z "${ZONE}" ]; then
        echo "UNKNOWN: Zone was not specified"
    fi
    if [ -z "${WARN}" ]; then
        echo "UNKNOWN: Warning threshold was not specified"
    fi
    if [ -z "${CRIT}" ]; then
        echo "UNKNOWN: Critical threshold was not specified"
    fi
    exit $STATE_UNKNOWN
fi

gatherOutput
compileData
printVerbose
printStatus

