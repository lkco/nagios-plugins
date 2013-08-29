#!/bin/bash
################################################################################
# 2013 Olivier LI-KIANG-CHEONG                                                 #
#                                                                              #
# This program is free software; you can redistribute it and/or modify         #
# it under the terms of the GNU General Public License as published by         #
# the Free Software Foundation; either version 2 of the License, or            #
# (at your option) any later version.                                          #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License along      #
# with this program; if not, write to the Free Software Foundation, Inc.,      #
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.                  #
#                                                                              #
################################################################################
# Version : 1.0                                                                #
################################################################################
# Author : Olivier LI-KIANG-CHEONG <lkco@gezen.fr>                             #
################################################################################
# CHANGELOG :                                                                  #
# 1.0 : initial release                                                        #
################################################################################
# DESCRIPTION :                                                                #
# Recorder selenium scenario on Xvfb display when nagios services ar not OK    #
# state type is HARD and checks are enabled                                    #
# Tested on : Centos 5, recordMyDesktop v0.3.8.1                               #
################################################################################


HISTORY_MONTH="1" # keep the history video in month
VIDEOPATH="/tmp/selenium/"
XVFBDISPLAY=":2"
PIDFILE="/var/run/recordmydesktop.pid"
RECORDER_LOG="/var/log/recordmydesktop.log"
RECORDER_OPTIONS="--display :2 --width 1024 --height 768 --no-sound --full-shots --fps 15 --v_quality 63 --s_quality 10 --v_bitrate 2000000 --delay 2"
LIVESTATUS_SOCKET_UNIX="/var/log/nagios/rw/live"

# Purge video
purge_dir=$(date -d "$HISTORY_MONTH month ago" "+%Y%m")
rm -fr /tmp/selenium/$purge_dir*

[ -e "/tmp/query" ] && rm -f /tmp/query

# Count services belonging Scenario_Web servicegroup, are not OK, HARD only, checks are enabled
# Debug : Columns: description state state_type plugin_output
cat << EOF >> /tmp/query
GET services
Filter: groups >= Scenario_Web
Filter: state > 0
Filter: checks_enabled = 1
Stats: state > 0
EOF

count_service_KO=$(unixcat $LIVESTATUS_SOCKET_UNIX < /tmp/query)

if [ "$count_service_KO" == "0" ]; then
    # Nothing to do, stop recordmydesktop if running
    if [ -e $PIDFILE ]; then
        PID=`cat ${PIDFILE}`
        kill -TERM ${PID} &> /dev/null
        rm -f ${PIDFILE}
    fi
    exit 0
fi

PID=`cat ${PIDFILE}`
PIDRUN=`ps -eaf | awk '{ print $2 }' | grep "^${PID}$"`
if [ -z "${PIDRUN}" ]; then
    echo "recordmydesktop is not running"
    # Start recordmydesktop
    videopath_with_date="$VIDEOPATH/$(date +%Y%m%d-%H)"
    mkdir -p $videopath_with_date
    cd $videopath_with_date
    /usr/bin/recordmydesktop $RECORDER_OPTIONS  >> $RECORDER_LOG 2>&1& 
    PID=$!
    RETVAL=$? 
    echo ${PID} > ${PIDFILE}
fi
