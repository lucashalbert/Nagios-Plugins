#!/bin/bash
print_version() {
    cat <<EOF
####################################################################################
#
# Author:       Lucas Halbert <https://www.lhalbert.xyz>
# Date:         07/25/2016
# Last Edited:  02/28/2019
# Version:      2019.02.28
# Description:  Checks the status of fail2ban-client for a command line specified
#               service.
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
#  Revisions:   2019.02.28  Add License and revision option to print revisions
#
#               2018.02.28  Add performance data
#
#               2016.07.25  Initial draft               
#
####################################################################################
EOF
}

print_usage() {
    cat <<EOF

Usage: $0 -j <jail-name> [-v|-vv|-vvv(verbosity) -V(version) -h|H(help)]

EOF

}
print_help() {
    cat <<EOF

$0 checks the status of a specific fail2ban jail

Usage: $0 -j <jail-name> [-v|-vv|-vvv(verbosity) -V(version) -h|H(help)]

EOF
}

F2BCLIENTBIN="/bin/sudo /bin/fail2ban-client"
WHITELIST=($(grep "^ignoreip" /etc/fail2ban/jail.local | awk -F "= " '{print $2}'))
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
    temp=$(${F2BCLIENTBIN} status ${JAIL})
    if [[ "$?" -gt 0 ]]; then
        echo "UNKNOWN: ${temp}"
        exit $STATE_UNKNOWN
    fi
}

cidrSearch() {
    local result=""
    local cidr_address=$1
    local ip_base=$(echo ${cidr_address} | awk -F "/" '{print $1}')
    local cidr_mask=$(echo ${cidr_address} | awk -F "/" '{print $2}')
    local ip_octets=()
    ip_octets+=($(echo ${ip_base} | awk -F "." '{print $1}'))
    ip_octets+=($(echo ${ip_base} | awk -F "." '{print $2}'))
    ip_octets+=($(echo ${ip_base} | awk -F "." '{print $3}'))
    ip_octets+=($(echo ${ip_base} | awk -F "." '{print $4}'))
    #echo "octets: ${ip_octets[*]}"
    #echo "cidr_address: ${cidr_address}"
    #echo "ip_base: ${ip_base}"
    #echo "cidr_mask: ${cidr_mask}"

    if (( cidr_mask >= 8 )) && (( cidr_mask < 16 )); then
        #echo Class A :
        local SUBNETHOSTS=$(( $(( 2**$(( 16-cidr_mask )) )) -1 ))
        local REGEX="${ip_octets[0]}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"
        local result=$(echo ${BANNEDIPS} | grep -E -o ${REGEX})
    elif (( cidr_mask >= 16 )) && (( cidr_mask < 24 )); then
        #echo Class B :
        local SUBNETHOSTS=$(( $(( 2**$(( 24-cidr_mask )) )) -1 ))
        local REGEX="${ip_octets[0]}\.${ip_octets[1]}\.[0-9]{1,3}\.[0-9]{1,3}"
        local result=$(echo ${BANNEDIPS} | grep -E -o ${REGEX})
    elif (( cidr_mask >= 24 )) && (( cidr_mask < 32 )); then
        #echo Class C : 
        local SUBNETHOST=$(( $(( 2**$(( 32-cidr_mask )) )) -1 ))
        local REGEX="${ip_octets[0]}\.${ip_octets[1]}\.${ip_octets[2]}\.[0-9]{1,3}"
        local result=$(echo ${BANNEDIPS} | grep -E -o ${REGEX})
    fi
    if [[ ! -z ${result} ]] ; then
        echo ${result}
    else
        return 0
    fi
}

compileData() {
    CURRENTFAILED=$(echo "${temp}" | grep "Currently failed:" | awk '{print $5}')
    TOTALFAILED=$(echo "${temp}" | grep "Total failed:" | awk '{print $5}')
    CURRENTBANNED=$(echo "${temp}" | grep "Currently banned:" | awk '{print $4}')
    TOTALBANNED=$(echo "${temp}" | grep "Total banned:" | awk '{print $4}')
    BANNEDIPS=$(echo "${temp}" | grep "Banned IP list:" | awk -F ":" '{print $2}' | sed "s/^\s\+//")

    # check if BANNEDIPs contains whitelist IPs
    for i in ${WHITELIST[@]}; do
        local searchResult=$(cidrSearch ${i})
        if [[ ! -z ${searchResult} ]]; then
            STATE=$(echo -e "${STATE}\nCRITICAL: Whitelisted IPs ${searchResult} currently blocked")
        fi
    done

    # Compile State Data
    STATE=$(echo "${STATE}\nCurrently Failed: ${CURRENTFAILED}")
    STATE=$(echo "${STATE}\nTotal Failed: ${TOTALFAILED}")
    STATE=$(echo "${STATE}\nCurrently Banned: ${CURRENTBANNED}")
    STATE=$(echo "${STATE}\nTotal Banned: ${TOTALBANNED}")
    #STATE=$(echo "${STATE}\nBanned IPs: ${BANNEDIPS}")
    
    # Compile Performance Data
    PERFDATA+=($(echo "CURRENTFAILED=${CURRENTFAILED};${CURRENTWARN};${CURRENTCRIT};;"))
    PERFDATA+=($(echo "TOTALFAILED=${TOTALFAILED};${TOTWARN};${TOTCRIT};;"))
    PERFDATA+=($(echo "CURRENTBANNED=${CURRENTBANNED};${CURRENTWARN};${AVECRIT};;"))
    PERFDATA+=($(echo "TOTALBANNED=${TOTALBANNED};${TOTWARN};${TOTCRIT};;"))
}

printVerbose() {
	# Print Verbose Info
	if [ "$VERBOSE" -gt 0 ]; then
	    echo "#---- Debug Info ----#"
	    if [ "$VERBOSE" -gt 1 ]; then
                echo verbosity level 2
            if [ "$VERBOSE" -gt 2 ]; then
                echo verbosity level 3
            fi
        fi
        echo -e "Currently Failed: ${CURRENTFAILED}"
        echo -e "Total Failed: ${TOTALFAILED}"
        echo -e "Currently Banned: ${CURRENTBANNED}"
        echo -e "Total Banned: ${TOTALBANNED}"
        echo -e "Banned IPs: ${BANNEDIPS}"
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

while getopts ":j:vVhH" opt; do
    case $opt in
      j)
        JAIL=$OPTARG
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
      \*)
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
