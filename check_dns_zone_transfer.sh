#!/bin/bash
print_version() {
    cat <<EOF
####################################################################################
#
#  Author:         Lucas Halbert <contactme@lhalbert.xyz>
#  Date:           06/19/2018
#  Last Edited:    06/19/2018
#  Version:        2018.06.19
#  Purpose:        Nagios plugin to verify that zone transfers are occuring
#  Description:    Performs a zone transfer using dig to verify that BIND ACLs and
#                  rndc TSIG keys are configured properly
#  License:        BSD 3-Clause License
#
#  Copyright (c) 2017, Lucas Halbert
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
#  Revisions:   2018.06.19  Initial draft
#
####################################################################################
EOF
}

print_usage() {
    cat <<EOF

$0 Nagios plugin to verify that zone transfers are occuring

Usage: $0 -S server -Z zone -T key:md5-key -W ms -C ms [-t <seconds>] [-v]

EOF
}

print_help() {
    cat <<EOF
NAME
       $(basename $0)

SYNOPSIS
       $0 -S server -Z zone -T key:md5-key -W ms -C ms [-t <seconds>] [-v]

DESCRIPTION
       $0 - Verifies zone transfers work using the provided arguments 

      -S|--server)
        SERVER=$2; shift 2 ;;
      -T|--tsig)
        TSIG=$2; shift 2 ;;
      -Z|--zone)
        ZONE=$2; shift 2 ;;
      -W|--warn)
        WARN=$2; shift 2 ;;
      -C|--crit)
        CRIT=$2; shift 2 ;;
      -t|--timeout)
        TIMEOUT=$2; shift 2 ;;
      -v)
        VERBOSE=$((VERBOSE+1)); shift ;;
      -V|--version)
        print_version
        print_changelog

OPTIONS
       -S|--server hostname
              Server hostname to query

       -T|--tsig transfer signature
              Transfer signature in the form of key:tsig

       -Z|--zone zone
              Zone to query

       -W|--warn ms
              Query warning time in milliseconds

       -C|--crit ms
              Query critical time in milliseconds

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
TYPE="AXFR"
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
    digOutput=$(dig +dnssec ${TYPE} ${ZONE} -y ${TSIG} @${SERVER})
    echo "${digOutput}" | grep NOERROR 1>/dev/null
    if [[ "$?" -gt 0 ]]; then
        echo "ERROR: ${TYPE} transfer for ${ZONE} failed"
        echo "$digOutput" | grep "^;;"
        exit $STATE_CRITICAL
    fi
}

compileData() {
    local queryTime=$(echo "$digOutput" | grep "Query time:" | cut -d ' ' -f 4)
    local transferSize=$( echo "$digOutput" | grep "XFR size:" | cut -d ' ' -f 9)
    local transferSizeRecords=$( echo "$digOutput" | grep "XFR size:" | cut -d ' ' -f 4)

    if [[ "$CRIT" && "$WARN" ]]; then
        PERFDATA+=($(echo "${ZONE}=${queryTime}ms;${WARN};${CRIT};0;1000"))
        # Check Query time
        if [ $(echo ${queryTime} ${CRIT} |awk '{print ($1 > $2) ? "true" : "false" }') = "true" ]; then
            STATE=$(echo "Query time CRITICAL: ${ZONE} ${TYPE} transfer took ${queryTime}ms")
        elif [ $(echo ${queryTime} $WARN |awk '{print ($1 > $2) ? "true" : "false" }') = "true" ]; then
            STATE=$(echo "Query time WARNING: ${ZONE} ${TYPE} transfer took ${queryTime}ms")
        else
            STATE=$(echo "Query time OK: ${ZONE} ${TYPE} transfer took ${queryTime}ms")
        fi
    fi
}

printVerbose() {
    # Print Verbose Info
    if [ "$VERBOSE" -gt 0 ]; then
        echo "#---- Debug Info ----#"
        echo "Server: ${SERVER}"
        echo "Zone: ${ZONE}"
        echo "TSIG: ${TSIG}"
        echo "Type: ${TYPE}"
        echo "Timeout: ${TIMEOUT} seconds"
        echo "Warn Threshold: ${WARN}ms"
        echo "Crit Threshold: ${CRIT}ms"
        if [ "${VERBOSE}" -eq 2 ]; then
            echo "${digOutput}" | grep "^;;"
        elif [ "${VERBOSE}" -eq 3 ]; then
            echo "${digOutput}"
        fi
        echo -e "#-- End Debug Info --#\n"
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

OPTS=$(getopt -o S:Z:W:C:T:t:vVhH --long help,server:,tsig:,zone:,warn:,crit:,timeout:,verbose,version -- "$@")
if [ $? != 0 ]; then
    echo "Failed parsing options." >&2;
    exit $STATE_UNKNOWN
fi

eval set -- "$OPTS"
while true; do
    case "$1" in
      -S|--server)
        SERVER=$2; shift 2 ;;
      -T|--tsig)
        TSIG=$2; shift 2 ;;
      -Z|--zone)
        ZONE=$2; shift 2 ;;
      -W|--warn)
        WARN=$2; shift 2 ;;
      -C|--crit)
        CRIT=$2; shift 2 ;;
      -t|--timeout)
        TIMEOUT=$2; shift 2 ;;
      -v)
        VERBOSE=$((VERBOSE+1)); shift ;;
      -V|--version)
        print_version
        print_changelog
        exit $STATE_OK
        ;;
      -h)
        print_usage
        exit $STATE_OK
        ;;
      -H|--help)
        print_help
        exit $STATE_OK
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

if [ -z "$SERVER" -o -z "$TSIG" -o -z "$ZONE" -o -z "$WARN" -o -z "$CRIT" ]; then
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
