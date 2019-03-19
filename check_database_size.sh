#!/bin/bash
print_version() {
    cat <<EOF
####################################################################################
#
# Author:       Lucas Halbert <contactme@lhalbert.xyz>
# Date:         12/01/2015
# Last Edited:  02/28/2019
# Version:      2019.28.02
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
#  Revisions:   2019.02.28  Add License and fix missing argument test
#
#               2017.03.17  Add Performance Data output to use with pnp4nagios
#
#               2015.12.01  Initial draft
#
####################################################################################
EOF
}

print_usage() {
    cat <<EOF

Usage: $0 -h <host> -u <user> -p <password> -w <db warning size> -c <db critical size> -W <total warning size> -C <total critical size> [-d <database>] [-v|-vv|-vvv]

Usage: $0 -h <host> -u <user> -p <password> -w <db warning size> -c <db critical size> -d <database> [-v|-vv|-vvv]

Usage: $0 -h <host> -u <user> -p <password> -W <total warning size> -C <total critical size> [-v|-vv|-vvv]

EOF
}
print_help() {
    cat <<EOF

$0 checks the size of MySQL databases and returns the status for nagios

Usage: $0 -h <host> -u <user> -p <password> -w <db warning size> -c <db critical size> -W <total warning size> -C <total critical size> [-d <database>] [-v|-vv|-vvv]

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
	output=$(echo 'SELECT table_schema "Data Base Name", sum( data_length + index_length ) / 1024 / 1024 "Data Base Size in MB" FROM information_schema.TABLES GROUP BY table_schema;' | mysql -h $HOST -u $USER -p$PASS)
    storeOutput=$output
	if [ "$?" -gt 0 ]; then
	    echo "CRITICAL: MySQL connection can not be made"
	    echo "$output"
	    exit $STATE_CRITICAL
	fi
    output=$(echo "$output" | sed -e '/Data Base/d' -e '/schema/d' -e '/mysql/d' | awk '{printf "%-25s: %10.2f MB\n", $1,$2}')

    if [ "$DATABASE" ]; then
        output=$(echo "$output" | grep "$DATABASE")
        if [ "$?" -gt 0 ]; then
            echo "CRITICAL ${DATABASE} does NOT exist"
            exit $STATE_CRITICAL
        fi
    fi
}

compileData() {
	while read -r line; do
	    DB=$(echo "$line" | awk '{print $1}')
	    size=$(echo "$line" | awk '{print $3}')
	    TOTAL_SIZE=$(echo $size $TOTAL_SIZE | awk '{sum=($1 + $2); print sum}')
	
	    if [[ "$CRIT" && "$WARN" ]]; then
            PERFDATA+=($(echo "${DB}=${size}MB;${WARN};${CRIT};0;$((${CRIT} + 100))"))
	        # Check DB Sizes
	        if [ `echo $size $CRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
	            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "CRITICAL ${DB}" ": ${size} MB")
	        elif [ `echo $size $WARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
	            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "WARNING ${DB}" ": ${size} MB")
	        else
	            STATE=$(printf "%s\n%-20s %-10s\n" "${STATE}" "OK ${DB}" ": ${size} MB")
	        fi
	    fi
	done <<< "$output"
	
	if [[ "$TOT_CRIT" && "$TOT_WARN" ]]; then
	    PERFDATA+=($(echo "Total=${TOTAL_SIZE}MB;${TOT_WARN};${TOT_CRIT};0;1000"))
	    # Check Total Size
	    if [ `echo $TOTAL_SIZE $TOT_CRIT |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
		        STATE=$(printf "%-20s %-10s %s" "CRITICAL Total Size" ": ${TOTAL_SIZE} MB" "${STATE}")
		    elif [ `echo $TOTAL_SIZE $TOT_WARN |awk '{print ($1 < $2) ? "true" : "false" }'` = "false" ]; then
		        STATE=$(printf "%-20s %-10s %s" "WARNING Total Size" ": ${TOTAL_SIZE} MB" "${STATE}")
		    else
		        STATE=$(printf "%-20s %-10s %s" "OK Total Size" ": ${TOTAL_SIZE} MB" "${STATE}")
		fi
    fi
	}
	
printVerbose() {
	# Print Verbose Info
	if [ "$VERBOSE" -gt 0 ]; then
	    echo "#---- Debug Info ----#"
        if [ "$VERBOSE" -gt 1 ]; then
            echo "# Raw Output #"
            echo "$storeOutput"
	        if [ "$VERBOSE" -gt 2 ]; then
	            echo DB Host: $HOST
	            echo DB User: $USER
	            echo DB Pass: $PASS
            fi
	    fi
	    echo DB Warning Size: ${WARN}
	    echo DB Critical Size: ${CRIT}
	    echo Total Warning Size: ${TOT_WARN}
	    echo Total Critical Size: ${TOT_CRIT}
	    echo Selected DB: ${DATABASE}
	    echo Total Size: ${TOTAL_SIZE} MB
	    printf "%-25s:%10s\n" "Database" "Size"
        s=$(printf "%-25s:%15s\n" "-" "-")
        echo "${s// /-}"
	    echo "$output"
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

while getopts ":h:u:p:w:c:W:C:d:vVH" opt; do
    case $opt in
      h)
        HOST=$OPTARG
        ;;
      u)
        USER=$OPTARG
        ;;
      p)
        PASS=$OPTARG
        ;;
      w)
        WARN=$OPTARG
        ;;
      c)
        CRIT=$OPTARG
        ;;
      W)
        TOT_WARN=$OPTARG
        ;;
      C)
        TOT_CRIT=$OPTARG
        ;;
      d)
        DATABASE=$OPTARG
        ;;
      v)
        VERBOSE=$((VERBOSE+1))
        ;;
      V)
        print_version
        print_changelog
        exit $STATE_OK
        ;;
      H)
        print_help
        print_usage
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
compileData
printVerbose
printStatus

