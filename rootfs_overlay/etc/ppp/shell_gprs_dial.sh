#!/bin/sh
#
# shell_gprs_dial.sh
#
# Package mobile-data-connector 
# Shell-script based GPRS/UMTS/LTE mobile data network dial script
#
# Copyright (c) 2009-2023, SWARCO Traffic Systems GmbH
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
#     2009-08-28 gc: initial version
#

echo $0 [Version 2023-07-05 16:04:50 gc]

#GPRS_DEVICE=/dev/ttyS0
#GPRS_DEVICE=/dev/com1
#GPRS_BAUDRATE=115200
#. /etc/default/gprs
#GPRS_DEVICE=/dev/com1

GPRS_STATUS_FILE=/tmp/gprs-stat
GPRS_NET_STATUS_FILE=/tmp/gprs-net
echo -n >$GPRS_STATUS_FILE

GRPS_ERROR_COUNT_FILE=/tmp/gprs-error
GPRS_ERROR_COUNT_MAX=4


# echo file descriptor to raw AT commands and received answer from
# terminal adapter
# if comment out, no echo of AT command chat
AT_VERBOSE_FD=1

cr=`echo -n -e "\r"`


##############################################################################
# Shell functions
##############################################################################

set_gprs_led() {
    echo 0 "$*" >/tmp/gprs_led
}

if [ -x /opt/swarco/bin/sys-mesg ]; then
    SYS_MESG=/opt/swarco/bin/sys-mesg
elif [ -x /usr/swarco/bin/sys-mesg ]; then
    SYS_MESG=/usr/swarco/bin/sys-mesg
else
    SYS_MESG=/usr/weiss/bin/sys-mesg
fi
sys_mesg() {
    test -x $SYS_MESG && $SYS_MESG -n GPRS "$@"

}
# internationalization functions for messages (identity)
N_() {
  echo "$@"
}

M_() {
  echo "$@"
}

sys_mesg_net() {
    test -x $SYS_MESG && $SYS_MESG -n GPRS_NET "$@"

}


sys_mesg_remove() {
    test -x $SYS_MESG && $SYS_MESG -n GPRS -r
}


# extract part of string by regular expression
re_extract() {
   awk "/$1/ {print gensub(/.*$1.*/,\"\\\\1\",1)}"                              
}                                                                               

# print log message
print() {
    echo "$*"
}


status() {
    local var=$1
    shift
    case var in
        GPRS_CSQ)
            local low_limit=10
            local net=GSM
            if grep -E "HSDPA|HSUPA|WCDMA|HSPA" /tmp/gprs-net 2>/dev/null; then
                low_limit=5
                net=UMTS
            fi
            if [ $1 -lt $low_limit ]; then
                sys_mesg_net -e NET -p warning `M_ "Low $net signal quality" `
            else
                sys_mesg_net -e NET -p okay `M_ "No error" `
            fi
    esac
    awk "! /^$var=/ {  print } END { print \"$var='$*'\" }" <$GPRS_STATUS_FILE >${GPRS_STATUS_FILE}.tmp
    mv ${GPRS_STATUS_FILE}.tmp ${GPRS_STATUS_FILE}
}

status_net() {
    print "Network: $*"
    echo -n >$GPRS_NET_STATUS_FILE "$*"

}
status_net unknown

print_at_cmd()
{
    if [ \! -z "$AT_VERBOSE_FD" ]; then
        if [ \! -z "$PRINT_AT_CMD_FILTER" ]; then
            eval echo '>&$AT_VERBOSE_FD' "$PRINT_AT_CMD_FILTER"
        else
            echo >&$AT_VERBOSE_FD "$*"
        fi
    fi
}

print_rcv() {
      # echo removes leading / trailing whitespaces
      if ! [ -z "`echo -n $1`" ]; then
          print_at_cmd "RCV: $1"
      fi
}

error() {
# not supported by most TAs
#    at_cmd "AT+CERR"
#    print "Extended error report: $r"

    exit 1
}

reset_terminal_adapter() {
    print "Reseting terminal adapter"
    if [ \! -z "$GPRS_RESET_CMD" ]; then
        /bin/sh -c "$GPRS_RESET_CMD"
        exec 3<>/dev/null
        fuser -k -9 $GPRS_DEVICE
        sleep 60
        exec 3<>$GPRS_DEVICE
    else
        case $TA_VENDOR in
            WAVECOM)
                at_cmd "AT+CFUN=1"
                exec 3<>/dev/null
                fuser -k -9 $GPRS_DEVICE
                sleep 60
                exec 3<>$GPRS_DEVICE
                ;;

            SIEMENS | Cinterion )
                at_cmd "AT+CFUN=1,1"
                exec 3<>/dev/null
                fuser -k -9 $GPRS_DEVICE
                sleep 60
                exec 3<>$GPRS_DEVICE
                ;;

            *)
                print "Don't known how to reset terminal adapter $TA_VENDOR"
                #try Siemens command
                at_cmd "AT+CFUN=1,1"
                # close file handle, so device (e.g. /dev/ttyUSB0) can be realloced
                exec 3<>/dev/null
                fuser -k -9 $GPRS_DEVICE
                sleep 60
                exec 3<>$GPRS_DEVICE
                ;;
        esac
    fi
}

send() {
  print_at_cmd "SND: $1"
  echo -e "$1\r" >&3 &
}

command_mode() {
  sleep 2
  print_at_cmd "SND: +++ (command mode)"
  # IMPORTEND: To enter command mode +++ is followed by a delay of 1000ms
  #            There must not follow a line feed character after +++
  #            so use -n option!
  echo -ne "+++">&3&
  sleep 2
}


wait_quiet() {
#  print "wait_quiet $1"
  local wait_time=2
  local wait_str=""
  if [ "0$1" -gt 0 ]; then wait_time=$1; fi
  if [ \! -z "$2" ]; then wait_str="$2"; fi
  local start_time=`date +%s`
  local line=""
  while IFS="" read -r -t$wait_time line<&3
  do
      #remove trailing carriage return
      line=${line%%${cr}*}
      print_rcv "$line"

      if [ `date +%s` -ge $((start_time+wait_time)) ]; then
          print "wait_quiet -- FORCED timeout"
          break
      fi

      if [ \! -z "$wait_str" ]; then
#          print "wq: str -${wait_str}-"
          case $line in
              *"${wait_str}"*)
#                  print_at_cmd "got wait: $wait_str"
                  return 1
                  ;;

              *)
                  ;;
          esac
#      else 
#          print "wq: no str"
      fi
  done
#  print "wait_quiet finished"
  return 0
}


# execute AT cmd and wait for "OK"
# Params: 1 AT Command String
#         2 Wait time in seconds (default 10)
#         3 Additional WAIT string
# Result $r Result string
line_break=" "
at_cmd() {
  # r is returned to caller
  r=""
  local wait_time=2
  local count=0
  local wait_str="OK"
  local echo_rcv=""

  if [ "0$2" -gt 0 ]; then wait_time=$2; fi
  if [ \! -z "$3" ]; then wait_str="$3"; fi

  wait_quiet 1

  print_at_cmd "SND: $1"
  echo -e "$1\r" >&3 &

  while true
  do
      local line=""
      if ! IFS="" read -r -t$wait_time line <&3
      then
          sys_mesg -e TA_AT -p warning `M_ "AT command timeout" `
          print timeout
          return 2
      fi
      #remove trailing carriage return
      line="${line%%${cr}*}"
      print_rcv "$line"
      #suppress echo of AT command in result string
      if [ -z "$echo_rcv" -a "$line" = "$1" ]; then echo_rcv="x"; continue; fi
      if [ -z "$r" ]; then
	r="$line"
      else
        r="$r$line_break$line"
      fi
      case $line in
          *OK*)
              return 0
              ;;
          *"${wait_str}"*)
#              print_at_cmd "got wait: $wait_str"
              return 0
              ;;

          *ERROR*)
              return 1
              ;;
      esac
      count=$(($count+1))
      if [ $count -gt 15 ]
      then
          sys_mesg -e TA_AT -p warning `M_ "AT command timeout" `
          print timeout
          return 2
      fi
  done

  if [ -d /proc/$! ]; then echo TTY driver hangs; return 3; fi
  return 0
}


# sendsms phonenum "text"
sendsms() {
    wait_quiet 1
    send "AT+CMGS=\"$1\""
    wait_quiet 20 "AT+CMGS="
    send "$2\\032"

    while true
    do
        local line=""
        IFS="" read -r -t5 line<&3 || break;

        #remove trailing carriage return
        line=${line%%${cr}*}
        print_rcv "$line"
        case $line in
            *OK* )
                print sending SMS sucessfully
                return 0;
                ;;

            *ERROR*)
                print ERROR sending SMS
                return 1
                break;
                ;;
        esac
    done

    return 1
}

query_signal_quality() {
    at_cmd "AT+CSQ"
    print "Signal quality: ${r%% OK}"
    r=${r##*CSQ: }
    GPRS_CSQ=${r%%,*}
    status GPRS_CSQ $GPRS_CSQ
}

query_board_temp() {
    at_cmd "AT^SCTM?"
    r=${r##^SCTM: *,*,}
    GPRS_TEMP="${r%% OK}"
    print "Board temperature: ${GPRS_TEMP}°C"

    if [ $GPRS_TEMP -gt 60 ]; then
        sys_mesg_net -e NET -p warning `M_ "High modem temperature " `
    else
        sys_mesg_net -e NET -p okay `M_ "No error" `
    fi
    status GPRS_TEMP $GPRS_TEMP
}


##############################################################################
# load modules and detect ttyUSB* devices (2018-03-09 gc: deprecated)
##############################################################################
find_usb_device() {
    local reload_modules=$1
    local vendor=$2
    local product=$3
    local dev_app=$4
    local dev_mod=$5

    if [ \! -z "$reload_modules" ]; then
        exec 3<>/dev/null
        fuser -k -9 $GPRS_DEVICE
        sleep 1
        rmmod usbserial; modprobe usbserial vendor=0x$vendor product=0x$product
        sleep 1
    fi

    for l in 1 2 3 4 5
    do
        if [ -c "$dev_app" ]; then
            # Application port
            GPRS_DEVICE_APP="$dev_app"
            GPRS_DEVICE=$GPRS_DEVICE_APP
            if [ \! -z "$dev_mod" -a -c "$dev_mod" ]; then
                # Modem Port
                GPRS_DEVICE_MODEM="$dev_mod"
            fi
            break
        fi
        sleep 2
    done

    # force module reload if no device is found!
    if [ -z "$GPRS_DEVICE_APP" ]; then
        rmmod usbserial; modprobe usbserial vendor=0x$vendor product=0x$product
        sleep 1
        for l in 1 2 3 4 5
        do
            if [ -c "$dev_app" ]; then
            # Application port
                GPRS_DEVICE_APP="$dev_app"
                GPRS_DEVICE=$GPRS_DEVICE_APP
                if [  \! -z "$dev_mod" -a -c "$dev_mod" ]; then
                # Modem Port
                    GPRS_DEVICE_MODEM="$dev_mod"
                fi
                break
            fi
            sleep 2
        done
    fi
}

get_device_by_usb_interface()
{
    local dev_path=$1
    local if_num=$2

    (
        cd $dev_path/*:1.$if_num
        if [ -d tty ] ; then
            echo "/dev/`ls tty`"
        else
            echo "/dev/`echo tty*`"
        fi
    )
    
}

##############################################################################
# load modules and detect ttyACM* devices by specifying USB interface numbers
# for application and modem port
##############################################################################
find_usb_device_by_interface_num() {
    local reload_modules=$1
    local dev_path=$2
    local if_num_app=$3
    local if_num_mod="$4"
    local vendor=$5
    local product=$6

    if [ \! -z "$reload_modules" -a \! -z "$vendor" -a \! -z "$product"  ]; then
        exec 3<>/dev/null
        fuser -k -9 $GPRS_DEVICE
        sleep 1
        rmmod usbserial; modprobe usbserial vendor=0x$vendor product=0x$product
        sleep 2
    fi
    
    echo "app interface bInterfaceClass: `cat $dev_path/*:1.$if_num_app/bInterfaceClass`"
    #    GPRS_DEVICE_APP="/dev/`ls $dev_path/*:1.$if_num_app/tty`"
    GPRS_DEVICE_APP=`get_device_by_usb_interface "$dev_path" $if_num_app`
    GPRS_DEVICE=$GPRS_DEVICE_APP
    #    GPRS_DEVICE_MODEM="/dev/`ls $dev_path/*:1.$if_num_mod/tty`"
    if ! [ -z "$if_num_mod" ]; then
        echo "modem interface bInterfaceClass: `cat $dev_path/*:1.$if_num_mod/bInterfaceClass`"
        GPRS_DEVICE_MODEM=`get_device_by_usb_interface "$dev_path" $if_num_mod`
    fi
#    GPRS_BAUDRATE=115200
    GPRS_BAUDRATE=921600
    
    # wait until devices have setteled
    for l in 1 2 3 4 5
    do
        #echo "app: $GPRS_DEVICE_APP, mod: $if_num_mod, ($GPRS_DEVICE_MODEM)"
        if [ -c "$GPRS_DEVICE_APP" -a \( -z "$if_num_mod" -o -c "$GPRS_DEVICE_MODEM" \) ]; then
            return
        fi
        sleep 2
    done
    echo "Devices $GPRS_DEVICE_APP or $GPRS_DEVICE_MODEM not found"
}

print_usb_device() {
    echo "found $1"
    status GPRS_DEVICE_USB "$1"
}

##############################################################################
# Driver loading and initialisation of special (USB) devices
##############################################################################
init_and_load_drivers() {
    local reload_modules=$1
    # huaweiAktBbo and usb_modeswitch only work with mounted usbfs
    if ! [ -f /proc/bus/usb/devices ]; then
        mount -tusbfs none /proc/bus/usb
    fi

    for id in /sys/bus/usb/devices/*
    do
        case `cat $id/idVendor 2>/dev/null`:`cat $id/idProduct 2>/dev/null` in
            :)
                continue
                ;;

        # Huawei E220, E230, E270, E870
        12d1:1003)
                local d=
                print_usb_device "Huawei Technologies Co., Ltd. E220 HSDPA Modem"
                # 2016-03-31 gc: huaweiAktBbo is now replaced by usb_modeswitch
                usb_modeswitch -v 12d1 -p 1003 -C 0xff --huawei-mode 
                find_usb_device "$reload_modules" 12d1 1003 /dev/ttyUSB0
                ;;

        #  Huawei E1750 in mass storage device mode
        12d1:1446)
                local d=
                print_usb_device "Huawei Technologies Co., Ltd. E1750 HSDPA Modem in mass storage mode"
                usb_modeswitch -v 12d1 -p 1446 -M 55534243123456780000000000000011062000000100000000000000000000
                exit 1
                ;;

        12d1:1436)
                print_usb_device "Huawei Technologies Co., Ltd. E1750 HSDPA Modem in USB serial mode"
                find_usb_device "$reload_modules" 12d1 1436 /dev/ttyUSB0
                ;;

        #  Huawei E303/E353/E3131 in mass storage device mode
        12d1:1f01 | 12d1:1446)
                local d=
                print_usb_device "Huawei Technologies Co., Ltd. E303/E353/E3131 HSDPA Modem in mass storage mode"

                usb_modeswitch -v 12d1 -p `cat $id/idProduct` -M 55534243123456780000000000000011060000000000000000000000000000
                exit 1
                ;;

        12d1:1001 | 12d1:1506)
                print_usb_device "Huawei Technologies Co., Ltd. E303/E353/E3131 HSDPA Modem in USB serial mode"
                find_usb_device "$reload_modules" 12d1 `cat $id/idProduct` /dev/ttyUSB2 /dev/ttyUSB0
                ;;

        0681:0041)
                print_usb_device "Siemens HC25 in USB mass storage mode"

                sleep 1

                for scsi in /sys/bus/scsi/devices/*
                do
                    #echo check: $scsi: `cat $scsi/model`
                    case `cat $scsi/model` in
                        *HC25\ flash\ disk*)
                            #echo path: "$scsi/block:"*
                            local x=`readlink $scsi/block\:*`
                            local dev=${x##*/}
                            if [ \! -z "$dev" ]; then
                                echo "ejecting Siemens HC25 in USB mass storage device: /dev/$dev"
                                eject "/dev/$dev"
                                exit 1
                            fi
                            ;;
                    esac
                done
                ;;

            0681:0040)
                print_usb_device "Siemens HC25 in USB component mode"

                find_usb_device "$reload_modules" 0681 0040 /dev/ttyUSB0 /dev/ttyUSB2
                ;;


            0681:0047)
                print_usb_device "Siemens HC25 in USB CDC-ACM mode"

                find_usb_device "$reload_modules" 0681 0047 /dev/ttyUSB0 /dev/ttyACM0
                ;;

            1e2d:0053)
                print_usb_device "Cinterion PH8 in USB component mode"
                find_usb_device_by_interface_num "1" $id 2 "" 1e2d 0053
                print "first USB port is $GPRS_DEVICE"
                # find_usb_device "" 1e2d 0053 /dev/ttyUSB3
                sleep 1
                initialize_port $GPRS_DEVICE
                sleep 1
                # connect file handle 3 with terminal adapter
                exec 3<>$GPRS_DEVICE
                at_cmd 'AT'
                at_cmd "AT^SDPORT?"
                case "$r" in
                    *'^SDPORT: 3'*)
                        print "Service Interface Allocation 3: Okay"
                        ;;
                    *)
                        print "Must switch to Interface Allocation 3"
                        at_cmd "AT^SDPORT=3"
                        exit 1
                        ;;
                esac

                find_usb_device_by_interface_num "" $id 2 3
                ;;

            1e2d:0054)
                print_usb_device "Cinterion PH8 in USB CDC-ACM mode"

                find_usb_device "" 1e2d 0054 /dev/ttyACM0
                # switch to USB component mode
                sleep 1
                initialize_port $GPRS_DEVICE
                sleep 1
                # connect file handle 3 with terminal adapter
                exec 3<>$GPRS_DEVICE
                at_cmd "AT^SDPORT=3"
                sleep 1
                exit 1
                ;;

            1e2d:0058)
                print_usb_device "Cinterion EHS5-E in USB CDC-ACM mode"

                #find_usb_device "$reload_modules" 1e2d  0058 /dev/ttyACM0 /dev/ttyACM3
                find_usb_device_by_interface_num "$reload_modules" $id 0 6
                ;;


            1e2d:0061)
                print_usb_device "Cinterion PLS8-E"

                find_usb_device_by_interface_num "$reload_modules" $id 2
                #find_usb_device "$reload_modules" 1e2d  0061 /dev/ttyACM1
                sleep 1
                initialize_port $GPRS_DEVICE
                sleep 1
                exec 3<>$GPRS_DEVICE
                at_cmd 'AT'
                at_cmd 'AT^SSRVSET="actSrvSet"'
                case "$r" in
                    *'^SSRVSET: 2'*)
                        print "Service Interface Configuration 2: Okay"
                        ;;
                    *)
                        print "Must switch to Service Interface Configuration 2"
                        #switch to service set 2
                        # so we have
                        # Modem Interface at /dev/ttyACM0
                        # Application Interface at /dev/ttyACM1
                        at_cmd 'AT^SSRVSET="actSrvSet",2'

                        # new service set is active after reset
                        reset_terminal_adapter
                        exit 1
                        ;;
                esac
                find_usb_device_by_interface_num "$reload_modules" $id 2 0
                ;;


            114f:1234)
                print_usb_device "Wavecom Fastrack Xtend FXT003/009 CDC-ACM Modem"
                ;;

            1bc7:1004)
                print_usb_device "Telit UC864-G 3G Module"
                TA_VENDOR="Telit"
                TA_MODEL="UC864"
                find_usb_device "" 1bc7 1004 /dev/ttyUSB0
                ;;

            1bc7:0021)
                print_usb_device "Telit HE910 3G Module"
                TA_VENDOR="Telit"
                TA_MODEL="HE910"

                # find_usb_device "" 1bc7 0021 /dev/ttyACM0
                # sleep 1
                # initialize_port $GPRS_DEVICE
                find_usb_device_by_interface_num "$reload_modules" $id 0 6
                ;;

            1bc7:1201)
                print_usb_device "Telit LE910C4-EU 4G Module"
                TA_VENDOR="Telit"
                TA_MODEL="LE910"

                find_usb_device_by_interface_num "$reload_modules" $id 4 5
                ;;

            1bc7:0036)
                print_usb_device "Telic LT910 E"
                TA_VENDOR="Telit"
                TA_MODEL="LE910-EU1"

                find_usb_device_by_interface_num "$reload_modules" $id 0 6
                ;;

            esac
    done
}

##############################################################################
# Check vendor / model of connected terminal adapter
##############################################################################
identify_terminal_adapter() {
    at_cmd "ATi" || return 1
    print "Terminal adpater identification: $r"

    status GPRS_TA "${r%% OK}"

    case $r in
        *Cinterion* )
            TA_VENDOR=Cinterion
            case $r in
                *MC35*)
                    TA_MODEL=MC35
                    print "Found Cinterion MC35 GPRS terminal adapter"
                    ;;
                *MC52*)
                    TA_MODEL=MC52
                    print "Found Cinterion MC52 GPRS terminal adapter"
                    ;;
                *MC55*)
                    TA_MODEL=MC55
                    print "Found Cinterion MC55 GPRS terminal adapter"
                    ;; 
                *BG2-W*)
                    TA_MODEL=BG2-W
                    print "Found Cinterion BG2-W (MC-Technologies MC66) GPRS terminal adapter"
                    ;;
                *EGS5*)
                    TA_MODEL=EGS5
                    print "Found Cinterion EGS5 (MC-Technologies MC88i) GPRS terminal adapter"
                    GPRS_CMD_SET=1
                    ;;
                *HC25*)
                    TA_MODEL=HC25
                    print "Found Cinterion HC25 UMTS/GPRS terminal adapter"
                # HC25: enable network (UTMS=blue/GSM=green) status LEDs
                    at_cmd "AT^sled=1"
# 2011-08-01 gc: added the following two options to prevent
#                assignment of dummy DNS address "10.11.12.13"
#                on GPRS / UMTS terminal adapters (Siemens HC25, ...)
                   GPRS_PPP_OPTIONS="$GPRS_PPP_OPTIONS connect-delay 5000 ipcp-max-failure 30"
                    ;;
                *PHS8* | *PH8*)
                    TA_MODEL=PH8
                    print "Found Cinterion PH8/PHS8 HSDPA/UMTS/GPRS terminal adapter"
                    ;;

                *PLS8*)
                    TA_MODEL=PLS8
                    print "Found Cinterion PLS8 LTE/HSDPA/UMTS/GPRS terminal adapter"
                    ;;

                *EHS*)
                    TA_MODEL=EHS5
                    print "Found Cinterion EHSx HSDPA/UMTS/GPRS terminal adapter"
                    ;;
                *)
                    print "Found unkonwn Cinterion terminal adapter"
                    ;;
            esac
            ;;
        *SIEMENS* )
            TA_VENDOR=SIEMENS
            case $r in
                *TC35*)
                    TA_MODEL=TC35
                    print "Found Siemens TC35 GPRS terminal adapter"
                    ;;
                *MC35*)
                    TA_MODEL=MC35
                    print "Found Siemens MC35 GPRS terminal adapter"
                    ;;
                *HC25*)
                    TA_MODEL=HC25
                    print "Found Siemens HC25 UMTS/GPRS terminal adapter"
                # HC25: enable network (UTMS=blue/GSM=green) status LEDs
                    at_cmd "AT^sled=1"
                    ;;
                *)
                    print "Found unkonwn Siemens terminal adapter"
                    ;;
            esac
            ;;

        *WAVECOM* | *Sierra\ Wireless*)
            TA_VENDOR=WAVECOM

            case $r in
                *MULTIBAND\ \ 900E\ \ 1800*)
                    print "Found Wavecom Fastrack Supreme terminal adapter"
                    ;;

                *FXT009*)
                    TA_MODEL=FXT009
                    # 2014-09-22 gc: Bugfix Sierra Wireless FXT009:
                    #                GPRS_CMD_SET is general supported, but
                    #                will not work for Vodafone CDA APN!
                    #                (Firmware tested till R7.51.0.201306260837)
                    #GPRS_CMD_SET=1
                    # Bugfix on Sierra Wireless FXT009
                    # this device sometimes switchs baudrate after CSD 
                    # connect, so we set it here to fixed baudrate
                    # (only when connected to serial port)
                    # These device will not save +IPR setting permanent,
                    # when no AT&W command is issued, so after power reset
                    # the interface is reset to autobaud!
	            if ! [ -z "$GPRS_ANSWER_CSD_CMD" ]; then
                    # print "GPRS_DEVICE: $GPRS_DEVICE" 
	                case "$GPRS_DEVICE" in
		            /dev/com* | /dev/ttyS* | /dev/ttyAT*)
                                at_cmd "AT+IPR=$GPRS_BAUDRATE"
	                        ;;
                        esac
                    fi
                    print "Found Sierra Wireless / Wavecom FXT009 GPRS terminal adapter"
                    ;;
                *)
                    print "Found unknown Sierra Wireless / Wavecom GPRS terminal adapter"
                    ;;
            esac

            # Query WAVECOM reset timer for log
            at_cmd "AT+WRST?"
            ;;

        *huawei*)
            TA_VENDOR=HUAWEI
            case $r in
                *E17X*)
                    TA_MODEL=E17X
                    print "Found Huawei E17X terminal adapter"
                    ;;
                *)
                    print "Found unkonwn Huawei terminal adapter"
                    ;;
            esac
            ;;

        *)
            if [ -z "$TA_VENDOR$TA_MODEL" ]; then
                print "Found unkonwn terminal adapter"
            fi
            ;;
    esac
}


initialize_port() {
    local device=$1

    # prevent blocking when opening the TTY device due modem status lines
    if ! stty -F $device $GPRS_BAUDRATE clocal -crtscts -brkint -icrnl -imaxbel -opost -onlcr -isig -icanon -echo -echoe -echok -echoctl -echoke 2>&1 ; then

    # stty may say "no such device"
        print "stty failed"
    # 2012-10-11 gc: stty may only set a subset of the requested parameter,
    #                so we try to continue even if stty reports a error 
        return 0
    fi

    echo -n AT${cr} >$device &
    sleep 5
    if [ -d /proc/$! ]; then
        echo TTY driver hangs;
        return 1
    fi



    return 0
}


##############################################################################
# handle RING
##############################################################################
# 2009-08-28 gc: experimental, on ring
on_ring() {
    local count=0;
    local is_answered=0;

    echo on_ring

    while IFS="" read -r -t120 line<&3
    do
        line=${line%%${cr}*}
        print_rcv "$line"

        case $line in
            *RING*)
                send "ATA"
                is_answered=1;
                ;;
            *ERROR* | *NO*CARRIER*)
                if [ "$is_answered" -ne 0 ]; then
                    return 1
                fi
                ;;

            *CONNECT*)
                GPRS_ERROR_COUNT=0
                write_error_count_file
                echo starting $GPRS_ANSWER_CSD_CMD
                status_net "GSM / CSD connection active"
                set_gprs_led 50 1000

        # start in own shell to create new process group
        #sh -c "eval $GPRS_ANSWER_CSD_CMD" &
                eval "$GPRS_ANSWER_CSD_CMD" <&3 &
                rsm_pid=$!
                echo "GPRS_ANSWER_CSD_CMD started (pid $rsm_pid)"
                #cat /proc/$!/stat
                while [ -d /proc/$rsm_pid ]
                do
                    /usr/bin/modemstatus-wait dcd_lost pid $rsm_pid <&3
                    case $? in
                        3)
                            # DCD lost
                            echo DCD lost
                            status_net "GSM registered"
                            set_gprs_led off
                            # echo kill -INT $rsm_pid
                            # kill -INT $rsm_pid
                            # fuser /dev/com8
                            # sleep 5
                            # echo kill process group
                            # kill -9 -$rsm_pid
                            # fuser /dev/com8
                            #return 0;
                            # killing remote subnet manager currently is currently not working
                            # use fuser to kill all processes access our device
                            # (including us self)
                            echo killing
                            fuser -k -9 $GPRS_DEVICE
                            echo ready
                            exit 0
                            ;;
                        
                        64)
                # PROCESS PID Terminated
                            echo "GPRS_ANSWER_CSD_CMD terminated (pid $rsm_pid)"
                            break
                            ;;
                        
                        *)
                # error
                    # modemstatus-wait fails on TIOCGICOUNT ioctrl on devices
                            break
                            ;;
                    esac
                done
                set_gprs_led 1000 50 100 50
                fuser -k -9 $GPRS_DEVICE
                return 0
                ;;
        esac
        count=$(($count+1))
        if [ $count -gt 15 ]
        then
            print timeout
            set_gprs_led 1000 50
            return 2
        fi

    done


    set_gprs_led 1000 50

    # while IFS="" read -r -t120 line<&3
    # do
    #     line=${line%%${cr}*}
    #     print_rcv "$line"

    #     case $line in
    #         *RING*)

    #             #at_cmd "ATA" 90 "CONNECT" || return 1
    #             echo starting $GPRS_ANSWER_CSD_CMD
    #             # start in own shell to create new process group
    #             #sh -c "eval $GPRS_ANSWER_CSD_CMD" &
    #             eval "$GPRS_ANSWER_CSD_CMD" &
    #             rsm_pid=$!
    #             echo "GPRS_ANSWER_CSD_CMD started (pid $rsm_pid)"
    #             cat /proc/$!/stat
    #             while [ -d /proc/$rsm_pid ]
    #             do
    #                 /usr/bin/modemstatus-wait dcd_lost pid $rsm_pid <&3
    #                 case $? in
    #                     3)
    #                         # DCD lost
    #                         echo DCD lost
    #                         echo kill -INT $rsm_pid
    #                         kill -INT $rsm_pid
    #                         fuser /dev/com8
    #                         sleep 5
    #                         echo kill process group
    #                         kill -9 -$rsm_pid
    #                         fuser /dev/com8
    #                         #return 0;
    #                         ;;
                        
    #                     64)
    #             # PROCESS PID Terminated
    #                         ;;
                        
    #                     *)
    #             # error
    #                 # modemstatus-wait fails on TIOCGICOUNT ioctrl on devices
    #                         ;;
    #                 esac
    #             done
    #             return 0
    #             break;
    #             ;;

    #     esac

    #     count=$(($count+1))
    #     if [ $count -gt 15 ]
    #     then
    #         print timeout
    #         return 2
    #     fi

    # done
}

# get_break_count() {
#     k=${status##*brk:}
#     if [ "$k" == "$status" ]; then
#         b=0
#     else
#         b=${k%% *}
#     fi
# #    print "brk: $b"
# }


##############################################################################
# check and handle SMS
##############################################################################

check_and_handle_SMS() {
    # List UNREAD SMS
    local line=""
    local sms_ping=""
    local sms_reboot=""
    local sms_reconnect=""

    case "$TA_VENDOR $TA_MODEL" in
        *HUAWEI*)
            send 'AT+CMGL=0'
            ;;
        *)
            send 'AT+CMGL="REC UNREAD"'
            ;;
    esac
    while IFS="" read -r -t5 line<&3
    do
        line=${line%%${cr}*}
        print_rcv "$line"
        case $line in
            *OK*)
                break
                ;;
            *+CMGL:*)
              #extract SMS phone number
                SMS_NUM=${line##*\"REC UNREAD\",\"}
                SMS_NUM=${SMS_NUM%%\"*}
                print got phone $SMS_NUM
                ;;

            *"weisselectronic ping"*)
                sms_ping=$SMS_NUM
                ;;

            *"weisselectronic reconnect"*)
                sms_reconnect=$SMS_NUM
                ;;

            *"weisselectronic reboot"*)
                sms_reboot=$SMS_NUM
                ;;

            *)
                ;;
        esac
    done

    # delete all RECEIVED READ SMS from message store
    # fails with "+CMS ERROR: unknown error" if no RECEIVED READ SMS available
    # => IGNORE Error
    at_cmd "AT+CMGD=0,1"
    wait_quiet 1

    if [ \! -z "$sms_ping" ]; then
        sendsms $sms_ping "`hostname`: CSQ: $GPRS_CSQ `uptime`"
        # no reconnect
        return 0
    fi

    if [ \! -z "$sms_reconnect" ]; then
        sendsms $sms_reconnect "rc `hostname`: CSQ: $GPRS_CSQ `uptime`"
        return 1
    fi

    if [ \! -z "$sms_reboot" ]; then
        logger -t GPRS got reboot request per SMS
        sleep 10
        reboot
    fi
    return 1
}


##############################################################################
# attach PDP context to GPRS
##############################################################################
attach_PDP_context() {
    local result=0

    
    if [ -z "$GPRS_APN" ]; then
        print "The GPRS_APN env variable is not set"
        sys_mesg -e APN -p error `M_ "The GPRS_APN env variable is not set. Configuration error" `
        exit 1
    fi
    
    print "Entering APN: $GPRS_APN"
    at_cmd "AT+CGDCONT=1,\"IP\",\"$GPRS_APN\"" 240
    
    case $? in
        0)
            print "Successfully entered APN"
            ;;
        
        1)
            print "ERROR entering APN"
            error
            ;;
        
        *)
            print "TIMEOUT entering APN"
            error
            ;;
    esac
    
    at_cmd "AT+CGACT?"
    print "PDP Context attach: $r"
    wait_quiet 1

    case "$TA_VENDOR $TA_MODEL" in
        *Cinterion*PLS8*)
            if [ \! -z "$GPRS_USER" ]; then
                # Warning: Password / User name swapped compared to
                # Cinterion EHS5!
                PRINT_AT_CMD_FILTER='${*/^SGAUTH=1,2,\"*\",\"*\"/^SGAUTH=1,2,\"<hidden>\",\"$GPRS_USER\"}' \

                at_cmd "AT^SGAUTH=1,2,\"$GPRS_PASSWD\",\"$GPRS_USER\"" 10
            fi
            ;;

        *Cinterion*EHS*)
            if [ \! -z "$GPRS_USER" ]; then
                # Cinterion EHS5 must be provided with PDP credentials 
                # addition to ppp negation using AT^SGAUTH
                PRINT_AT_CMD_FILTER='${*/^SGAUTH=1,2,\"*\",\"*\"/^SGAUTH=1,2,\"$GPRS_USER\",\"<hidden>\"}' \

                at_cmd "AT^SGAUTH=1,2,\"$GPRS_USER\",\"$GPRS_PASSWD\"" 10
            fi
            ;;
    esac

    
#GPRS_CMD_SET=1
    
    if [ \! -z "$GPRS_DEVICE_MODEM" ]; then
# use a separate modem device for PPP connection,
# AT command interpreter on application port remains still accessible
# connect file handle 3 with modem device
        print "Switching to modem interface $GPRS_DEVICE_MODEM"
        if  initialize_port $GPRS_DEVICE_MODEM; then
            
            exec 3<>$GPRS_DEVICE_MODEM
            for l in 1 2 3 4 5
            do
                if at_cmd "AT"; then
                    break
                fi
                if [ "$l" == 5 ]; then
                    print "FAILED to talk with modem interface $GPRS_DEVICE_MODEM"
                    exit 1
                fi
                sleep 1
            done
        else
            GPRS_DEVICE_MODEM=""
        fi
    fi

    if [ -f /etc/ppp/peers/mobile-broadband ]; then
        PEER=mobile-broadband
    else
        PEER=gprs
    fi
    ppp_args="call $PEER nolog nodetach $GPRS_PPP_OPTIONS"
    if [ \! -z "$GPRS_USER" ]; then
        ppp_args="$ppp_args user $GPRS_USER"
    fi
    if [ \! -z "$GPRS_PASSWD" ]; then
        print "running pppd: /usr/sbin/pppd ${ppp_args} password <hidden>"
        ppp_args="$ppp_args password $GPRS_PASSWD"
    else
        print "running pppd: /usr/sbin/pppd ${ppp_args}"
    fi
    
    case $TA_VENDOR in
        *)
            if [ \! -z "$GPRS_DEVICE_MODEM" ]; then
                PPP_DEVICE="$GPRS_DEVICE_MODEM"
            else
                PPP_DEVICE="$GPRS_DEVICE"
            fi

             if [ \! -z "$GPRS_CMD_SET" ]; then
                 at_cmd "AT+GMI"
# activate PDP context
                 at_cmd "AT+CGACT=1,1" 90 || error
                 at_cmd "AT" 2
                
#enter data state
                 case $TA_VENDOR in
                     WAVECOM)
                         PPP_DIAL='AT+CGDATA=1'
                         ;;
                     SIEMENS | Cinterion | *)
                         PPP_DIAL='AT+CGDATA=\"PPP\",1'
                         ;;
                 esac
                
             # 2009-08-07 gc: AT+CGDATA dosn't deliver DNS addresses on
             # Siemens! BUG?
             else
                 PPP_DIAL='ATD*99***1#'
             fi
            

            #2011-04-11 gc: Sierra Wireless WAVECOM FXT009 response so fast
            #               on GPRS ATD command, so ppp frames will be lost.
            #               We must call pppd using a chat script for 
            #               dialing
            /usr/sbin/pppd $ppp_args  \
                connect "/usr/sbin/chat  -v TIMEOUT 120 \
                                            ABORT BUSY \
                                            ABORT 'NO CARRIER' \
                                            '' AT OK \
                                            '$PPP_DIAL' CONNECT" \
                <&3 >&3 &
#                $PPP_DEVICE $GPRS_BAUDRATE &
# save pppd's PID file in case of pppd hangs before it writes the PID file
            ppp_pid=$!
            echo $ppp_pid >/var/run/ppp0.pid
            status_net "PDP context attached (GPRS or UMTS)"

            # 2018-03-21 gc: reset error count on successfully PDP context attach
            GPRS_ERROR_COUNT=0
            write_error_count_file


# #            Experimential: Use USB-CDC Networking interface on PLS-8
#              at_cmd "AT+CGACT=0,1"
#              at_cmd "AT+CGACT?"
#              at_cmd "AT+CGPADDR=1" 2

             
#              at_cmd "AT^SWWAN=1,1,1" 90 || (at_cmd "AT+CERR"; error)
#              iptables -D INPUT -i usb1 -j ACCEPT
#              iptables -A INPUT -i usb1 -j ACCEPT

#              ifconfig usb1 up
#              udhcpc -bn -i usb1
#              status_net "PDP context attached (GPRS or UMTS)"

# #            /usr/bin/modemstatus-wait ri break  <&3
#              GPRS_DEVICE_MODEM=$GPRS_DEVICE
#              ppp_pid=$$            
            ;;
        
#         *)
#             if [ \! -z "$GPRS_CMD_SET" ]; then
#                 at_cmd "AT+GMI"
#     # activate PDP context
#                 at_cmd "AT+CGACT=1,1" 90 || error
#                 at_cmd "AT" 2
                
#     #enter data state
#                 case $TA_VENDOR in
#                     WAVECOM)
#                         at_cmd "AT+CGDATA=1" 90 "CONNECT" || error
#                         ;;
#                     SIEMENS | Cinterion | *)
#                         at_cmd "AT+CGDATA=\"PPP\",1" 90 "CONNECT" || error
#                         ;;
#                 esac
                
#             # 2009-08-07 gc: AT+CGDATA dosn't deliver DNS addresses on
#             # Siemens! BUG?
#             else
#                 at_cmd "AT D*99***1#" 90 "CONNECT" || error
#             fi
            
#             #sleep 1
#             stty -F $GPRS_DEVICE -ignbrk brkint
#             /usr/sbin/pppd $ppp_args <&3 >&3 &
# # save pppd's PID file in case of pppd hangs before it writes the PID file
#             ppp_pid=$!
#             echo $ppp_pid >/var/run/ppp0.pid
#             status_net "PDP context attached (GPRS or UMTS)"
#             ;;
    esac


    if [ \! -z "$GPRS_DEVICE_MODEM" ]; then
# reconnect file handle 3 on application interface
        print "Switching to application interface $GPRS_DEVICE"
        exec 3<>$GPRS_DEVICE
        for l in 1 2 3 4 5
        do
            if at_cmd "AT"; then
                break
            fi
        done
    fi

    case "$TA_VENDOR $TA_MODEL" in
        *SIEMENS*HC25* | *Cinterion*HC25* | *Cinterion*PH8* | *Cinterion*EHS5* | *Cinterion*PLS8*)
            if [ \! -z "$GPRS_DEVICE_MODEM" ]; then
                count=360
                while [ -d /proc/$ppp_pid ]
                do
                    # answer on ^SQPORT should be "Application" not "Modem"!
                    # at_cmd "AT^SQPORT"
                    count=$(($count+1))
                    if [ $count -gt 360 ]
                    then
                        count=0
                        #
                        case "$TA_VENDOR $TA_MODEL" in
                            *Cinterion*EHS* | *Cinterion*PLS8*)
                                query_board_temp
                                ;;
                        esac

                        query_signal_quality

                        # query Packet Switched Data Information:
                        at_cmd 'AT^SIND="psinfo",2'
                        case "$r" in
                            *'^SIND: psinfo,0,0'*)
                                status_net "no (E)GPRS available in current cell"
                                ;;
                            *'^SIND: psinfo,0,10'*)
                                status_net "UMTS: attached in HSDPA/HSUPA-capable cell"
                                ;;
                            *'^SIND: psinfo,0,16'*)
                                status_net "LTE: camped on EUTRAN capable cell"
                                ;;
                            *'^SIND: psinfo,0,17'*)
                                status_net "LTE: attached in EUTRAN capable cell"
                                ;;
                            *'^SIND: psinfo,0,1'*)
                                status_net "GSM: GPRS available"
                                ;;
                            *'^SIND: psinfo,0,2'*)
                                status_net "GSM: GPRS attached"
                                ;;
                            *'^SIND: psinfo,0,3'*)
                                status_net "EDGE: EGPRS available"
                                ;;
                            *'^SIND: psinfo,0,4'*)
                                status_net "EDGE: EGPRS attached"
                                ;;
                            *'^SIND: psinfo,0,5'*)
                                status_net "UMTS: camped on WCDMA cell"
                                ;;
                            *'^SIND: psinfo,0,6'*)
                                status_net "UMTS: WCDMA PS attached"
                                ;;
                            *'^SIND: psinfo,0,7'*)
                                status_net "UMTS: camped on HSDPA-capable cell"
                                ;;
                            *'^SIND: psinfo,0,8'*)
                                status_net "UMTS: attached in HSDPA-capable cell"
                                ;;
                            *'^SIND: psinfo,0,9'*)
                                status_net "UMTS: camped on HSDPA/HSUPA-capable cell"
                                ;;
                        esac
                    fi
                   #

                    while [ -d /proc/$ppp_pid ]  && IFS="" read -r -t10 line<&3
                    do
                        line=${line%%${cr}*}
                        print_rcv "APP_PORT: $line"
                        case $line in
                            *+CMTI:* | *+CMT:*)
                                echo SMS URC received
                                if ! check_and_handle_SMS; then
                                    kill -TERM $ppp_pid
                                fi
                                ;;
                            *RING*)
                                print "ringing"
                                on_ring
                                break;
                                ;;
                        esac
                    done
                    sleep 1
                done
            fi
            # wait till pppd process has terminated
            wait
            ;;


        *HUAWEI*)
            if [ \! -z "$GPRS_DEVICE_MODEM" ]; then
                while [ -d /proc/$ppp_pid ]  && IFS="" read -r -t10 line<&3
                do
                    line=${line%%${cr}*}
                    case $line in
                        *+CMTI:*|*+CMT:*)
                            echo SMS URC received
                            if ! check_and_handle_SMS; then
                                kill -TERM $ppp_pid
                            fi
                            ;;

                        *^MODE:*)
                            local m1=${line##*^MODE: }
                            local sys_mode=${m1%%,*}
                            local sub_mode=${line##*^MODE: *,}
                            local huawei_net=
                            local huawei_sub=

                            echo "Mode line received: $line ( ${line##*^: } ) $sys_mode $sub_mode"
                            case "$sys_mode" in
                                0)
                                    huawei_net="No service"
                                    ;;
                                1)
                                    huawei_net="AMPS"
                                    ;;
                                2)
                                    huawei_net="CDMA"
                                    ;;
                                3)
                                    huawei_net="GSM/GPRS"
                                    ;;
                                4)
                                    huawei_net="HDR"
                                    ;;
                                5)
                                    huawei_net="WCDMA"
                                    ;;
                                6)
                                    huawei_net="GPS"
                                    ;;
                                *)
                                    huawei_net="unknown"
                                    ;;
                            esac

                            case "$sub_mode" in
                                0)
                                    huawei_sub="No service"
                                    ;;
                                1)
                                    huawei_sub="GSM"
                                    ;;
                                2)
                                    huawei_sub="GPRS"
                                    ;;
                                3)
                                    huawei_sub="EDGE"
                                    ;;
                                4)
                                    huawei_sub="WCDMA"
                                    ;;
                                5)
                                    huawei_sub="HSDPA"
                                    ;;
                                6)
                                    huawei_sub="HSUPA"
                                    ;;
                                7)
                                    huawei_sub="HSDPA and HSUPA"
                                    ;;
                                8)
                                    huawei_sub="TD-SCDMA"
                                    ;;
                                9)
                                    huawei_sub="HSPA+"
                                    ;;
                                *)
                                    huawei_sub="unknown"
                                    ;;
                            esac
                            status_net "$huawei_net $huawei_sub"
                            ;;
                        
                        *^RSSI:*)
                            echo "RSSI line received: $line ( ${line##*^RSSI: } )"
                            GPRS_CSQ=${line##*^RSSI: }
                            status GPRS_CSQ $GPRS_CSQ    
                            ;;

                        *^DSFLOWRPT:*)
                            # 2016-05-03 gc: TODO
                            ;;
                        *RING*)
                            print "ringing"
                            on_ring
                            break;
                            ;;                        
                        *)
                            if ! [ -z "$line" ]; then
                                print_rcv "APP_PORT: $line"
                            fi
                    esac
                done
                sleep 1
            fi
            # wait till pppd process has terminated
            wait
            ;;

        *Telit*)
            if [ \! -z "$GPRS_DEVICE_MODEM" ]; then
                count=360
                while [ -d /proc/$ppp_pid ]
                do
                    count=$(($count+1))
                    if [ $count -gt 360 ]
                    then
                        count=0
                        #
                        query_signal_quality

                        # query Packet Switched Data Information:
                        at_cmd 'AT#PSNT?'
                        case "$r" in
                            *'#PSNT: 0,0'*)
                                status_net "GPRS network"
                                ;;
                            *'#PSNT: 0,1'*)
                                status_net "EGPRS network"
                                ;;
                            *'#PSNT: 0,2'*)
                                status_net "WCDMA network"
                                ;;
                            *'#PSNT: 0,3'*)
                                status_net "HSDPA network"
                                ;;
                            *'#PSNT: 0,4'*)
                                status_net "LTE network"
                                ;;
                            *)
                                status_net "unknown network"
                                ;;
                        esac
                    fi

                    while [ -d /proc/$ppp_pid ]  && IFS="" read -r -t10 line<&3
                    do
                        line=${line%%${cr}*}
                        print_rcv "APP_PORT: $line"
                        case $line in
                            *+CMTI:* | *+CMT:*)
                                echo SMS URC received
                                if ! check_and_handle_SMS; then
                                    kill -TERM $ppp_pid
                                fi
                                ;;
                            *RING*)
                                print "ringing"
                                on_ring
                                break;
                                ;;
                        esac
                    done
                    sleep 1
                done
            fi
            # wait till pppd process has terminated
            wait
            ;;

        *)
            print "waiting for modem status change"
            /usr/bin/modemstatus-wait ri break pid $ppp_pid <&3
            case $? in
                1)
                # RING
                    echo got RING
                    kill -TERM $ppp_pid
                    ring_recv=1
                    ;;

                2)
                # BREAK
                    echo BREAK received
                    kill -TERM $ppp_pid
                    ;;

                64)
                # PROCESS PID Terminated
                    result=1
                    ;;

                *)
                # error
                    # modemstatus-wait fails on TIOCGICOUNT ioctrl on devices
                    # not supporting it (for instance ttyACM)
                    # so we wait here for pppd's termination

                    #kill -TERM $ppp_pid
                    #do_restart=0
                    ;;
            esac

            # wait till pppd process has terminated
            wait
            ;;
    esac

    command_mode
    return $result
}

write_error_count_file() {

    cat >$GRPS_ERROR_COUNT_FILE <<FILE_END
# GRPS-Error Count, do not edit!
GPRS_ERROR_COUNT=$GPRS_ERROR_COUNT
FILE_END

true
}

##############################################################################
# Main
##############################################################################
set_gprs_led off

##############################################################################
# load and increment error count
##############################################################################
if [ -f $GRPS_ERROR_COUNT_FILE ] ; then
    . $GRPS_ERROR_COUNT_FILE
else
    GPRS_ERROR_COUNT=0
fi

GPRS_ERROR_COUNT=$((GPRS_ERROR_COUNT + 1))    
write_error_count_file

print GPRS_ERROR_COUNT: $GPRS_ERROR_COUNT

# 2020-03-11 gc: 
# if we have a hardware modem reset facility (GPRS_RESET_CMD is set)
# we can reset the modem even when errors in the initialization phase happens
# (e.g. device /dev/ttyUSB* not present in case of USB communication errors)
if [ \! -z "$GPRS_RESET_CMD" -a $GPRS_ERROR_COUNT -ge $GPRS_ERROR_COUNT_MAX ]
then
    reset_terminal_adapter
    init_and_load_drivers 1
    GPRS_ERROR_COUNT=$(($GPRS_ERROR_COUNT_MAX - 2))
    write_error_count_file
    exit 1
fi


if [ \! -z "$GPRS_START_CMD" ]; then
    /bin/sh -c "$GPRS_START_CMD"
fi

# reset "script-alive" watchdog
echo GPRS_WATCHDOG_COUNT=0 >/tmp/gprs-watchdog

if [ -f /var/run/ppp0.pid ]; then
    kill -INT `cat /var/run/ppp0.pid`
    rm /var/run/ppp0.pid
fi

##############################################################################
# Initialize device and/or load kernel modules on first start
##############################################################################
if [ -f $GRPS_ERROR_COUNT_FILE ] ; then
    init_and_load_drivers
else
    init_and_load_drivers 1
fi



##############################################################################
# Check if TTY device does not block after open
##############################################################################
if [ -c $GPRS_DEVICE ]; then

    print "Connecting mobile broadband. Device $GPRS_DEVICE (Modem: $GPRS_DEVICE_MODEM) ($GPRS_BAUDRATE baud)"
    
    status GPRS_DEVICE_CMD   "$GPRS_DEVICE"
    status GPRS_DEVICE_MODEM "$GPRS_DEVICE_MODEM"
    
    if ! initialize_port $GPRS_DEVICE; then
        sleep 10
        killall watchdog
        echo initializing port failed
        # 2012-10-11 gc: don't reboot here, we have gprs-watchdog now!
    #reboot
        exit 3
    fi
    
    # connect file handle 3 with terminal adapter
    exec 3<>$GPRS_DEVICE
    
    print "ready"
    
    #command_mode
    
    for l in 1 2 3 4 5
    do
        if at_cmd "AT"; then
            break
        else
            command_mode
            wait_quiet 1
        fi
    done

    case "$TA_VENDOR $TA_MODEL" in
        *Telit*)
            at_cmd "ATv1"
            ;;
        *)
            ;;
    esac
fi

##############################################################################
# check error count
##############################################################################


# check if modem need to be reseted by sending an AT command.
# (sending AT commands can be done only after initialization of serial port)
if [ $GPRS_ERROR_COUNT -ge $GPRS_ERROR_COUNT_MAX ] ; then
    print max err count reached
    # reload drivers in case /dev/ttyUSBxx device is not present
    init_and_load_drivers 1
    identify_terminal_adapter
    reset_terminal_adapter
    init_and_load_drivers 1
    GPRS_ERROR_COUNT=$(($GPRS_ERROR_COUNT - 2))
    write_error_count_file
    exit 1
fi

if ! at_cmd "AT"; then
    sys_mesg -e TA -p error `M_ "No response from terminal adapter, check connection" `
    exit 1
fi
print "Terminal adapter responses on AT command"
sys_mesg -e TA -p okay `M_ "No error" `
sys_mesg -e TA_AT -p okay `M_ "No error" `

# blink on pulse of 50ms for each 1000ms
set_gprs_led 1000 50


status GPRS_CONNECT_TIME `date "+%Y-%m-%d %H:%M:%S"`


# 2009-08-28 gc: hang up if there is a connection in background
# 2009-09-16 gc: ATH may block for longer time on bad reception conditions
#                =>Timeout 20
if ! at_cmd "ATH" 20; then
    # when ATH hangs, any character is used to abort command and is
    # not interpreted by terminal adapter
    at_cmd "AT"
    wait_quiet 5
fi


identify_terminal_adapter

##############################################################################
# Set verbose error reporting
##############################################################################
at_cmd "AT+CMEE=2"


##############################################################################
# Check and enter PIN
##############################################################################

#2009-08-07 gc: Wavecom only sends result code, no "OK"
if ! at_cmd "AT+CPIN?" 10 "+CPIN:"; then
    print result: $r
    err_msg=`echo $r | re_extract '\+CME ERROR: (.*)'`
    if [ \! -z "$err_msg" ]; then err_msg=": $err_msg"; fi
    sys_mesg -e SIM -p error `M_ "SIM card error" `
    # not translated message with embedded error message string
    sys_mesg -e NET -p error "SIM card error message: ${err_msg}"
    error
fi
wait_quiet 1

case $r in
    *'SIM PIN'*)
        if [ -z "$GPRS_PIN" ]; then
            sys_mesg -e SIM -p error `M_ "SIM card requires PIN" `
            print "ERROR: The GPRS_PIN env variable is not set"
            exit 1
        fi
        print "sending pin"
        # 2016-02-26 gc: Cinterion EHS5 module requires quotes around pin
	# hide PIN-Number from log, substitute with <hidden>
        PRINT_AT_CMD_FILTER='${*/+CPIN=\"????\"/+CPIN=<hidden>}' \
        at_cmd "AT+CPIN=\"$GPRS_PIN\"" 30 || error
        # Wait until registered
        if [ $TA_VENDOR == "WAVECOM" ]; then
            sleep 20
        else
            sleep 10
        fi
        ;;

    *READY*)
        ;;

    *'SIM PUK'*)
        sys_mesg -e SIM -p error `M_ "SIM card requires PUK" `
        exit 1
        ;;

    *)
        error
        ;;
esac
print "SIM ready"
sys_mesg -e SIM -p okay `M_ "No error" `

##############################################################################
# Select (manually) GSM operator
##############################################################################

op_cmd="AT+COPS=0"

case "$TA_VENDOR $TA_MODEL" in
    *Cinterion*EHS*)
        if [ \! -z "$GPRS_NET_ACCESS_TYPE" ]; then
            at_cmd "AT^SXRAT=$GPRS_NET_ACCESS_TYPE" 10
        else
            at_cmd "AT^SXRAT=1" 10
        fi
        ;;
    *HUAWEI*)
    case "$GPRS_NET_ACCESS_TYPE" in
        0)
            at_cmd "at^SYSCFG=13,2,3FFFFFFF,1,2" 10
            ;;
        2)
            at_cmd "at^SYSCFG=14,2,3FFFFFFF,1,2" 10
            ;;
        *)
            at_cmd "at^SYSCFG=2,2,3FFFFFFF,1,2" 10
            ;;
    esac
    ;;
esac

case "$TA_VENDOR $TA_MODEL" in
    *SIEMENS*HC25* | *Cinterion*HC25* | *Cinterion*PH8* | *Cinterion*PLS8* )
        # supply net access type (GSM or UMTS) for UMTS capable TA
        if [ \! -z "$GPRS_NET_ACCESS_TYPE" ]; then
            op_cmd="AT+COPS=0,,,$GPRS_NET_ACCESS_TYPE"
        fi


        if [ \! -z "$GPRS_OPERATOR" -a "$GPRS_OPERATOR" -ne 0 ]; then
            if [ \! -z "$GPRS_NET_ACCESS_TYPE" ]; then
                op_cmd="AT+COPS=1,2,\"$GPRS_OPERATOR\",$GPRS_NET_ACCESS_TYPE"
            else
                op_cmd="AT+COPS=1,2,\"$GPRS_OPERATOR\""
            fi
            print "Setting manual selected operator to $op_cmd"
        fi
        ;;

    *)
        if [ \! -z "$GPRS_OPERATOR" -a "$GPRS_OPERATOR" -ne 0 ]; then
            op_cmd="AT+COPS=1,2,\"$GPRS_OPERATOR\""
            print "Setting manual selected operator to $op_cmd"
        fi
        ;;
esac



at_cmd $op_cmd 90 || error


##############################################################################
# Wait for registration
##############################################################################
loops=0
network=""
while [ $loops -lt 120 ]
do
    at_cmd "AT+CREG?" 2
    case $r in
        *CREG:?0,1*)
            network="home"
            break
            ;;

        *CREG:?0,5*)
            network="roaming"
            break
            ;;

        *CREG:*)
            network="not registered"
            sys_mesg -e NET -p error `M_ "Failed to register on GSM/UMTS network" `
            ;;
    esac
    loops=$(($loops+1))
done

if [ -z "$network" ]; then
    print "No response from terminal adapter on AT+CREG?"

# wavecom modem sometimes don't respond on AT +CREG?
    if [ $TA_VENDOR != "WAVECOM" ]; then
        error
    fi
fi

status GPRS_ROAMING $network

if [ "$network" == "not registered" ]; then
  print "Failed to register on network"
  error
fi

# reset operator format to alphanumeric 16 characters
at_cmd "AT+COPS=3,0"
at_cmd "AT+COPS?"

print "res: $r"
r=${r#*\"}
r=${r%\"*}

print "Registered on $network network: $r"
sys_mesg -e NET -p okay `M_ "No error" `

status GPRS_NETWORK $r
# blink two pulses of 50ms for each 1000ms
set_gprs_led 1000 50 100 50

##############################################################################
# send user init string
##############################################################################

if [ \! -z "$GPRS_INIT" ]; then
    at_cmd $GPRS_INIT
    print "Result user init: $r"
fi


##############################################################################
# Data/CSD initialization
##############################################################################
# single numbering scheme: all incoming calls without "bearer
# capability" as DATA
at_cmd "AT+CSNS=4"
at_cmd "ATS0=0"

##############################################################################
# query some status information from terminal adapter
##############################################################################
  print "querying status information from terminal adapater:"
#
  at_cmd "AT+CGMM"
  print "Model Identification: ${r%% OK}"
  status GPRS_CGMM ${r%% OK}
#
  at_cmd "AT+CGMR"
  print "Firmware Version: ${r%% OK}"
  status GPRS_CGMR ${r%% OK}
#
  at_cmd "AT+CGSN"
  print "IMEI: ${r%% OK}"
  status GPRS_IMEI ${r%% OK}
#
  at_cmd "AT+CIMI"
  print "IMSI: ${r%% OK}"
  status GPRS_IMSI ${r%% OK}
#
  query_signal_quality

  case "$TA_VENDOR $TA_MODEL" in
      *Cinterion*EHS5* | *Cinterion*PLS8*)
          # EHSx / PLS8 don't support Siemens style AT^xMONx commands
          at_cmd "AT+CCID"
          print "SIM card id: $r"
          r=${r##+CCID: }
          status GPRS_SCID "${r%% OK}"

          at_cmd "AT^SCTM=0,1"
          query_board_temp
          ;;

      *SIEMENS* | *Cinterion* )
          case "$TA_MODEL" in
              *HC25*)
                  #PH8 supports ^SCID
                  ;;

              *)
                  at_cmd "AT^SCID"
                  print "SIM card id: $r"
                  r=${r##*SCID: }
                  status GPRS_SCID "${r%% OK}"
                  ;;
          esac
#
	  line_break="<br>"
          at_cmd "AT^MONI"
          status GPRS_MONI "${r%%<br>OK}"
#
          at_cmd "AT^MONP"
          status GPRS_MONP "${r%%<br>OK}"

          case "$TA_MODEL" in
              *HC25* | *TC35* | *PH8*)
                  ;;

              *)
                  at_cmd "AT^SMONG"
                  status GPRS_SMONG "${r%%<br>OK}"
                  ;;
          esac

  	  line_break=" "
          wait_quiet 5
          ;;

      *WAVECOM*)
          # query cell environment description 
          # @todo the output must be reformated
          # 2010-09-10 gc: dosn't work properly
          #at_cmd "AT+CCED=0,16" 60
          #status GPRS_CCED "${r%% OK}"
          ;;

  esac

# read on phone number
case "$TA_VENDOR $TA_MODEL" in
    *SIEMENS*MC35* | *SIEMENS*TC35* )
        at_cmd 'AT+CPBS="ON" +CPBR=1,4'
# +CPBR: 1,"+491752928173",145,"Eigene Rufnummer"  OK
        cnum=`echo $r | re_extract '\+CPBR: [0-9]+,"(\+?[0-9]+)",.*'`
        ;;

    *)
        at_cmd "AT+CNUM"
# +CNUM: "Eigene Rufnummer","+491752928173",145 OK
        cnum=`echo $r | re_extract '\+CNUM: "[^"]*","(\+?[0-9]+)",[.0-9]+.*'`
        ;;
esac

print "Own number: $r, num: $cnum"
status GPRS_NUM ${cnum}





##############################################################################
# SMS initialization
##############################################################################
# switch SMS to TEXT mode 
# TODO: Huawei don't support TEXT mode. 'The "text" mode is unable to
# display Chinese, so currently, only the PDU mode is used'
at_cmd "AT+CMGF=1"

#2009-08-28 gc: enable URC on incoming SMS (and break of data/GPRS connection)
case "$TA_VENDOR $TA_MODEL" in
    *SIEMENS*HC25* | *Cinterion*HC25* | *Cinterion*PH8* | *Cinterion*PLS8* | *Cinterion*EHS5*)
        at_cmd "AT+CNMI=2,1"
        ;;
    *WAVECOM*)
        at_cmd "AT+CNMI=2,1"
        # enable Ring Indicator Line on
        #   Bit 1: Incoming calls (RING)
        #   Bit 2: Incoming SMS (URCs: +CMTI; +CMT)
        at_cmd "AT+WRIM=1,$(((1<<2)+(1<<1))),33"
        ;;
    *)
        at_cmd "AT+CNMI=3,1"
        ;;
esac

if [ -z "$GPRS_ONLY_CSD" -o "$GPRS_ONLY_CSD" -eq 0 ]; then
    do_restart=16
    ring_wait_time=5
else
    do_restart=30
    ring_wait_time=60
    status_net "GSM registered"
fi
ring_recv=0

while [ $do_restart -ne 0 ]
do
    print "do_restart: $do_restart"
    do_restart=$(($do_restart-1))

    # reset "script-alive" watchdog
    echo GPRS_WATCHDOG_COUNT=0 >/tmp/gprs-watchdog

    case "$TA_VENDOR $TA_MODEL" in
        *HUAWEI*)
            # HUAWEI stick don't support CSQ mode, but sends a lot of URCs, so don't use wait_quit here!
            ;;
        *)
            if ! wait_quiet $ring_wait_time "RING" || [ $ring_recv -ne 0 ]; then
                on_ring
                echo back from on_ring
            fi
            ;;
    esac

    ring_recv=0
    check_and_handle_SMS

    if [ -z "$GPRS_ONLY_CSD" -o "$GPRS_ONLY_CSD" -eq 0 ]; then
        attach_PDP_context || do_restart=0
    else
        GPRS_ERROR_COUNT=0
        write_error_count_file
    fi
done

print "$0 terminated"
exit 0



# Local Variables:
# mode: shell-script
# time-stamp-pattern: "40/\\[Version[\t ]+%%\\]"
# backup-inhibited: t
# End:
