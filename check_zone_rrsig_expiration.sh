#!/bin/bash
print_version() {
    cat <<EOF
####################################################################################
#
# Author:       Lucas Halbert <https://www.lhalbert.xyz>
# Date:         03/17/2017
# Last Edited:  02/28/2019
# Version:      2019.02.28
# Description:  Checks the RRSIG expiration date of a DNSSEC signed DNS zone
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
#               2017.03.17  Initial draft
#
####################################################################################
EOF

}
print_usage() {
    cat <<EOF

$0 Checks the RRSIG expiration date of a DNSSEC signed DNS zone

Usage: $0 -S <server> -Z <zone> -T <record-type> -W <days> -C <days> [-t <seconds>] [-v] [-V] [-h] [-H]

EOF
}

print_help() {
    cat <<EOF
NAME
       $0 - Checks the RRSIG expiration date of a DNSSEC signed DNS zone

SYNOPSIS
       $0 -S <server> -Z <zone> -T <record-type> -W <days> -C <days> [-t <seconds>] [-v] [-V] [-h] [-H]

DESCRIPTION
       $0 - Checks the RRSIG expiration date of a DNSSEC signed DNS zone

OPTIONS
       -S|--server <hostname|IP>
              Server hostname to query

       -T|--type <query-type>
              Type of record to query (SOA, A, CNAME, DNS, etc...)

       -Z|--zone <zone>
              Zone to query

       -W|--warn <days>
              RRSIG expiration warning in days

       -C|--crit <days>
              RRSIG expiration critical in days

       -t|--timeout <seconds>
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
TYPE="SOA"
STATE=""
STATE_OK=0
STATE_CRITICAL=2
STATE_WARNING=1
STATE_UNKNOWN=3
VERBOSE=0
TOTAL_SIZE=0
declare -A RESULT
declare -a PERFDATA=("|")


gatherOutput() {
    RRSIGExpire=$(dig +dnssec +short ${TYPE} ${ZONE} @${SERVER} +time=${TIMEOUT} | grep ${TYPE} | awk '{print $5}' | tail -1)
    if [ -z "${RRSIGExpire}" ]; then
        echo "CRITICAL: No ${TYPE} RRSIG for ${ZONE}"
        echo "$output"
        exit $STATE_CRITICAL
    fi
}

compileData() {
    nowSeconds=$(date +'%s')
    RRSIGSeconds=$(date -d "${RRSIGExpire:0:4}-${RRSIGExpire:4:2}-${RRSIGExpire:6:2}T${RRSIGExpire:8:2}:${RRSIGExpire:10:2}:${RRSIGExpire:12:2}" '+%s')
    daysUntilExpire=$(( (${RRSIGSeconds}-${nowSeconds})/(60*60*24) ))
    if [[ "$CRIT" && "$WARN" ]]; then
        PERFDATA+=($(echo "${ZONE}=${daysUntilExpire}days;${WARN};${CRIT};0;$((${CRIT} + ${daysUntilExpire}))"))
        # Check RRSIG expiration
        if [ `echo ${daysUntilExpire} ${CRIT} |awk '{print ($1 < $2) ? "true" : "false" }'` = "true" ]; then
            STATE=$(echo "RRSIG CRITICAL: ${ZONE} RRSIG expires in ${daysUntilExpire}")
        elif [ `echo ${daysUntilExpire} $WARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "true" ]; then
            STATE=$(echo "RRSIG WARNING: ${ZONE} RRSIG expires in ${daysUntilExpire}")
        else
            STATE=$(echo "RRSIG OK: ${ZONE} RRSIG expires in ${daysUntilExpire}")
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
            echo "Record Type: ${TYPE}"
            echo "Timeout: ${TIMEOUT} seconds"
        fi
        echo "Now $(date +'%Y%m%d')"
        echo "RRSIG Expiration: ${RRSIGExpire}"
        echo "Now Seconds: ${nowSeconds}"
        echo "RRSIG Seconds: ${RRSIGSeconds}"
        echo "RRSIG Expires: ${daysUntilExpire}"
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

if [ "$#" -lt 1 ]; then
    print_usage
    exit 1
fi

OPTS=$(getopt -o S:Z:W:C:T:t:vVhH --long help,server:,zone:,warn:,crit:,type:,timeout:,verbose,version -- "$@")
if [ $? != 0 ]; then
    echo "Failed parsing options." >&2;
    exit $STATE_UNKNOWN
fi

eval set -- "$OPTS"
while true; do
    case "$1" in
      -S|--server)
        SERVER=$2; shift 2 ;;
      -Z|--zone)
        ZONE=$2; shift 2 ;;
      -W|--warn)
        WARN=$2; shift 2 ;;
      -C|--crit)
        CRIT=$2; shift 2 ;;
      -T|--type)
        TYPE=$2; shift 2 ;;
      -t|--timeout)
        TIMEOUT=$2; shift 2 ;;
      -v)
        VERBOSE=$((VERBOSE+1)); shift ;;
      -V|--version)
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
