#!/bin/bash
#!/bin/bash
print_version() {
    cat <<EOF
##########################################################################
#
# Author:       Lucas Halbert <https://www.lhalbert.xyz>
# Date:         12/23/2015
# Last Edited:  12/23/2015
# Version:      2015.12.23
# Description:  Checks the size of MySQL databases for nagios use.
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
#  Revisions:   2015.12.23  Initial draft
#
####################################################################################
EOF
}

print_usage() {
    cat <<EOF

Usage: $0 -s <CPU SOCKET[s]> -w <core warning temp> -c <core critical temp> -W <CPU warning temp> -C <CPU critical temp> [-v|-vv|-vvv]

Example: $0 -s 0 -w 55 -c 60 -W 65 -C 70 [-v|-vv|-vvv]

Example: $0 -s 0,1 -w 55 -c 60 -W 65 -C 70 [-v|-vv|-vvv]

EOF
}

print_help() {
    cat <<EOF

$0 checks CPU and Core temperatures via lm_sensors

Usage: $0 -s <CPU SOCKET[s]> -w <core warning temp> -c <core critical temp> -W <CPU warning temp> -C <CPU critical temp> [-v|-vv|-vvv]

EOF
}

STATE=""
STATE_OK=0
STATE_CRITICAL=2
STATE_WARNING=1
STATE_UNKNOWN=3
VERBOSE=0
declare -A RESULT
declare -a PERFDATA=("|")

gatherOutput() {
    if [[ $SOCKETS =~ "," ]]; then
        saveIFS=$IFS
        IFS=","
        read -r -a SOCKETS <<< "$SOCKETS"
        IFS=$saveIFS
    fi
    for SOCKET in "${SOCKETS[@]}"; do
        RESULT=$(sensors coretemp-isa-000${SOCKET})
        compileData
    done
}

compileData() {
    CPUTEMP=($(echo "${RESULT}" | grep "Physical id" | awk '{print $4}' | sed 's/+\([0-9]\+\.[0-9]\).*/\1/'))
    CPUS+=($(echo "${RESULT}" | grep "Physical id" | awk '{print $4}' | sed 's/+\([0-9]\+\.[0-9]\).*/\1/'))
    CORETEMPS=($(echo "${RESULT}" | grep "Core" | awk '{print $3}' | sed 's/+\([0-9]\+\.[0-9]\).*/\1/'))

    if [[ "$CPUCRIT" && "$CPUWARN" ]]; then
        PERFDATA+=($(echo "CPU${SOCKET}=${CPUTEMP}C;${CPUWARN};${CPUCRIT};0;120"))
        if [ `echo $CPUTEMP $CPUCRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "CRITICAL CPU${SOCKET}" ": ${CPUTEMP}C")
        elif [ `echo $CPUTEMP $CPUWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "WARNING CPU${SOCKET}" ": ${CPUTEMP}C")
        else
            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "OK CPU${SOCKET}" ": ${CPUTEMP}C")
        fi
    fi
    

    count=0
    for CORETEMP in "${CORETEMPS[@]}"; do
        CORES+=(${CORETEMP})

	    if [[ "$CORECRIT" && "$COREWARN" ]]; then
	        PERFDATA+=($(echo "CPU${SOCKET}:${count}=${CORETEMP}C;${COREWARN};${CORECRIT};0;120"))
	        if [ `echo $CORETEMP $CORECRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
	            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "CRITICAL CORE${count}" ": ${CORETEMP}C")
	        elif [ `echo $CORETEMP $COREWARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
	            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "WARNING CORE${count}" ": ${CORETEMP}C")
	        else
	            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "OK CORE${count}" ": ${CORETEMP}C")
	        fi
        fi
        ((count++))
    done
}

printVerbose() {
    # Print Verbose Info
    if [ "$VERBOSE" -gt 0 ]; then
        echo "#---- Debug Info ----#"
        echo CPU Warning Temp: ${CPUWARN}C
        echo CPU Critical Temp: ${CPUCRIT}C
        echo CORE Warning Temp: ${COREWARN}C
        echo CORE Critical Temp: ${CORECRIT}C
        if [ "$VERBOSE" -gt 1 ]; then
            echo "Num CPU Temps: ${#CPUS[@]}"
            echo "CPU Temps: ${CPUS[*]}"
            echo "Num CORE Temps: ${#CORES[@]}"
            echo "CORE Temps: ${CORES[*]}"
        fi
        if [ "$VERBOSE" -gt 2 ]; then
            echo ""
        fi
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
while getopts ":a:w:c:W:C:s:vVhH" opt; do
    case $opt in
      s)
        SOCKETS=$OPTARG
        ;;
      a)
        AVECRIT=$OPTARG
        ;;
      w)
        COREWARN=$OPTARG
        ;;
      c)
        CORECRIT=$OPTARG
        ;;
      W)
        CPUWARN=$OPTARG
        ;;
      C)
        CPUCRIT=$OPTARG
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
      H)
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
printVerbose
printStatus
