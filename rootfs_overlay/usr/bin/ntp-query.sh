#!/bin/sh
#
# ntp-query.sh
#
# Run NTP timeserver query as background process.  The ntpdate utility can run
# for several minutes until it has gotten a valid time in particular on a slow
# network connection (GPRS), a large timeout (-t option) and if many NTP-hosts
# are specified.
#
# Copyright (c) 2007-2017, SWARCO Traffic Systems GmbH
#                          Guido Classen <clagix@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Modification History:
#     2007-12-03 gc: initial version
#

NTPDATE=/usr/bin/ntpdate
HWCLOCK=/sbin/hwclock

# synchronize systime from NTP-Server
test -f $NTPDATE || exit 0
test -f /etc/default/ntpdate || exit 0

. /etc/default/ntpdate

test -n "$NTPSERVERS" || exit 0

. /etc/create_lock.sh
create_lock ntp-

# set -p 1 option when no -p option is specified
case $NTPOPTIONS in
    *-p*)
        ;;
    *)
        NTPOPTIONS="-p 1 $NTPOPTIONS"
        ;;
esac

logger -t $0 "Running ntpdate to synchronize clock"
if $NTPDATE $NTPOPTIONS $NTPSERVERS; then
    $HWCLOCK -w
    logger -t $0 "ntpdate finished with: `date`"
    if [ -f /etc/ppp/gprs-okay.sh ]; then
        sh /etc/ppp/gprs-okay.sh
    fi
else
    logger -t $0 "ntpdate FAILED"
    if [ -f /etc/ppp/gprs-fail.sh ]; then
        sh /etc/ppp/gprs-fail.sh
    fi
fi
