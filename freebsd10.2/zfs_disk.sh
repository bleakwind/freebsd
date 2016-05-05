#!/bin/sh
#
# $FreeBSD10.2: zfs_disk.sh,v 1.1 2015/10/14 08:45:18 Bleakwind (at) www.weaverdream.com Exp $
#
# - First when [Partitioning] select [Shell] and configure network:
#
# # ifconfig "em0" inet "192.168.8.201" netmask "255.255.255.0"
# # route add default "192.168.8.1"
# # echo "nameserver 202.96.134.133" >> /etc/resolv.conf
# # echo "nameserver 8.8.8.8" >> /etc/resolv.conf
#
# - Second fetch the shell file:
#
# # cd /tmp/
# # fetch https://raw.githubusercontent.com/bleakwind/freebsd/master/freebsd10.2/zfs_disk.sh && chmod +x zfs_disk.sh
# #     at: https://github.com/bleakwind/freebsd
#
# - Third allocating disk space:
#
# step 1
# # ./zfs_disk.sh -i zroot
#
# step 2
# # ./zfs_disk.sh -o
# # ./zfs_disk.sh -g da0 0 512k 4g 120g
#       or # ./zfs_disk.sh -g da0 0
# # ./zfs_disk.sh -g da1 1 512k 4g 120g
# # ./zfs_disk.sh -g da2 2 512k 4g 120g
# # ./zfs_disk.sh -g da3 3 512k 4g 120g
#
# step 3
# # ./zfs_disk.sh -p zroot "raidz2 da0p3 da1p3 da2p3 da3p3"
#       or: # ./zfs_disk.sh -p zroot "mirror da0p3 da1p3 mirror da2p3 da3p3"
#
# step 4
# # ./zfs_disk.sh -z zroot auto
# # ./zfs_disk.sh -z zroot "-o mountpoint=/pub zroot/pub"
# # ./zfs_disk.sh -z zroot "-o mountpoint=/db -o recordsize=8K zroot/db"
# #     option: -o copies=2
#
# step 5
# # ./zfs_disk.sh -f zroot
#
# step 6
# # rm zfs_disk.sh zfs_disk.sh.log
# # exit
#
# other
# # ./zfs_disk.sh -o
#       or: # ./zfs_disk.sh -o da0
# # ./zfs_disk.sh -h
#

THIS_FILE=$0
THIS_OPE=$1
FSTAB_FMT="%s\t\t%s\t%s\t%s\t\t%s\t%s\n"
HELP_INFO="usage: ${THIS_FILE} command args ...
where 'command' is one of the following:

    <init|-i> <poolname>
    <gpart|-g> <device> <label> [size_boot] [size_swap] [size_zfs]
    <pool|-p> <poolname> <"poolcommand">
    <zfs|-z> <poolname> <auto|"zfscommand">
    <finish|-f> <poolname> <"noplist">
    <info|-o> [device]
    <help|-h>"

if [ $# -le 0 ]; then
    echo "missing command"
    echo -e "${HELP_INFO}"
    exit 1
fi

if [ ! -f "${THIS_FILE}.log" ]; then
    echo -e "Log for ${THIS_FILE}: `date +%Y%m%d%H%M%S`" > ${THIS_FILE}.log
else
    echo -e "\nLog for ${THIS_FILE}: `date +%Y%m%d%H%M%S`" >> ${THIS_FILE}.log
fi
echo "\${THIS_FILE} > ${THIS_FILE}" >> ${THIS_FILE}.log
echo "\${THIS_OPE} > ${THIS_OPE}" >> ${THIS_FILE}.log

# begin
case "${THIS_OPE}" in
    # init: # ./zfs_disk.sh -i zroot
    init|-i)
        THIS_POOLNAME=$2

        if [ -z "${THIS_POOLNAME}" ]; then
            echo "missing argument"
            echo -e "${HELP_INFO}"
            exit 1
        fi
        echo "Begin init:" >> ${THIS_FILE}.log
        echo "\${THIS_POOLNAME} > ${THIS_POOLNAME}" >> ${THIS_FILE}.log

        zpool destroy "${THIS_POOLNAME}" >> ${THIS_FILE}.log 2>&1
        sysctl vfs.zfs.min_auto_ashift=12 >> ${THIS_FILE}.log 2>&1

        printf "" > "/tmp/bsdinstall_etc/fstab"
        printf "$FSTAB_FMT" "# Device" "Mountpoint" "FStype" "Options" "Dump" "Pass#" >> "/tmp/bsdinstall_etc/fstab"

        echo "End init---" >> ${THIS_FILE}.log
        echo "init successful..."
        ;;

    # gpart: # ./zfs_disk.sh -g da0 0 512k 4g 120g
    #    or: # ./zfs_disk.sh -g da0 0
    gpart|-g)
        THIS_DEVICE=$2
        THIS_LABEL=$3
        THIS_SIZE_BOOT=$4
        THIS_SIZE_SWAP=$5
        THIS_SIZE_ZFS=$6

        if [ -z "${THIS_DEVICE}" ] || [ -z "${THIS_LABEL}" ]; then
            echo "missing argument"
            echo -e "${HELP_INFO}"
            exit 1
        fi
        echo "Begin gpart---" >> ${THIS_FILE}.log

        if [ -z "${THIS_SIZE_BOOT}" ]; then
            THIS_SIZE_BOOT="512k"
        fi
        if [ -z "${THIS_SIZE_SWAP}" ]; then
            THIS_SIZE_SWAP=`sysctl hw.physmem | sed -e 's/.*hw\.physmem: \([0-9]*\).*/\1/g'`
            THIS_SIZE_SWAP=`echo "scale=2; ${THIS_SIZE_SWAP}/1024/1024/1024" | bc`
            THIS_SIZE_SWAP="`printf "%.0f" ${THIS_SIZE_SWAP}`g"
        fi

        echo "\${THIS_DEVICE} > ${THIS_DEVICE}" >> ${THIS_FILE}.log
        echo "\${THIS_LABEL} > ${THIS_LABEL}" >> ${THIS_FILE}.log
        echo "\${THIS_SIZE_BOOT} > ${THIS_SIZE_BOOT}" >> ${THIS_FILE}.log
        echo "\${THIS_SIZE_SWAP} > ${THIS_SIZE_SWAP}" >> ${THIS_FILE}.log
        echo "\${THIS_SIZE_ZFS} > ${THIS_SIZE_ZFS}" >> ${THIS_FILE}.log

        gpart destroy -F "${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1
        graid delete "${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1
        zpool labelclear -f "/dev/${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1
        gpart create -s gpt "${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1
        gpart destroy -F "${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1
        gpart create -s gpt "${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1

        THIS_BOOT=`gpart add -a 4k -l gptboot${THIS_LABEL} -t freebsd-boot -s ${THIS_SIZE_BOOT} "${THIS_DEVICE}"`
        THIS_BOOT_NAME=`echo ${THIS_BOOT} | sed -e 's/\([a-zA-Z0-9]*\) added/\1/g'`
        echo "\${THIS_BOOT} > ${THIS_BOOT}" >> ${THIS_FILE}.log 2>&1
        gpart bootcode -b "/boot/pmbr" -p "/boot/gptzfsboot" -i 1 "${THIS_DEVICE}" >> ${THIS_FILE}.log 2>&1

        THIS_SWAP=`gpart add -a 1m -l swap${THIS_LABEL} -t freebsd-swap -s ${THIS_SIZE_SWAP} "${THIS_DEVICE}"`
        THIS_SWAP_NAME=`echo ${THIS_SWAP} | sed -e 's/\([a-zA-Z0-9]*\) added/\1/g'`
        echo "\${THIS_SWAP} > ${THIS_SWAP}" >> ${THIS_FILE}.log 2>&1
        zpool labelclear -f "/dev/${THIS_SWAP_NAME}" >> ${THIS_FILE}.log 2>&1

        if [ -z "${THIS_SIZE_ZFS}" ]; then
            THIS_ZFS=`gpart add -a 1m -l zfs${THIS_LABEL} -t freebsd-zfs "${THIS_DEVICE}"`
        else
            THIS_ZFS=`gpart add -a 1m -l zfs${THIS_LABEL} -t freebsd-zfs -s ${THIS_SIZE_ZFS} "${THIS_DEVICE}"`
        fi
        THIS_ZFS_NAME=`echo ${THIS_ZFS} | sed -e 's/\([a-zA-Z0-9]*\) added/\1/g'`
        echo "\${THIS_ZFS} > ${THIS_ZFS}" >> ${THIS_FILE}.log 2>&1
        zpool labelclear -f "/dev/${THIS_ZFS_NAME}" >> ${THIS_FILE}.log 2>&1

        printf "${FSTAB_FMT}" "/dev/${THIS_SWAP_NAME}" "none" "swap" "sw" "0" "0" >> "/tmp/bsdinstall_etc/fstab"

        echo "remenber this => freebsd-boot:${THIS_BOOT_NAME}"
        echo "                 freebsd-swap:${THIS_SWAP_NAME}"
        echo "                 freebsd-zfs :${THIS_ZFS_NAME}"

        echo "End gpart---" >> ${THIS_FILE}.log
        echo "create partition successful..."
        ;;

    # pool: # ./zfs_disk.sh -p zroot "raidz2 da0p3 da1p3 da2p3 da3p3"
    #   or: # ./zfs_disk.sh -p zroot "mirror da0p3 da1p3 mirror da2p3 da3p3"
    pool|-p)
        THIS_POOLNAME=$2
        THIS_POOLCOMMAND=$3

        if [ -z "${THIS_POOLNAME}" ] || [ -z "${THIS_POOLCOMMAND}" ]; then
            echo "missing argument"
            echo -e "${HELP_INFO}"
            exit 1
        fi
        echo "Begin pool---" >> ${THIS_FILE}.log
        echo "\${THIS_POOLNAME} > ${THIS_POOLNAME}" >> ${THIS_FILE}.log
        echo "\${THIS_POOLCOMMAND} > ${THIS_POOLCOMMAND}" >> ${THIS_FILE}.log
        echo "zpool create -o altroot=/mnt -O compress=lz4 -O atime=off -m none -f "${THIS_POOLNAME}" ${THIS_POOLCOMMAND}" >> ${THIS_FILE}.log

        zpool create -o altroot=/mnt -O compress=lz4 -O atime=off -m none -f "${THIS_POOLNAME}" ${THIS_POOLCOMMAND} >> ${THIS_FILE}.log 2>&1
        zfs create -o mountpoint=none "${THIS_POOLNAME}/ROOT" >> ${THIS_FILE}.log 2>&1
        zfs create -o mountpoint=/ "${THIS_POOLNAME}/ROOT/default" >> ${THIS_FILE}.log 2>&1

        echo "End pool---" >> ${THIS_FILE}.log
        echo "create pool successful..."
        ;;

    # zfs: # ./zfs_disk.sh -z zroot auto
    #      # ./zfs_disk.sh -z zroot "-o mountpoint=/pub zroot/pub"
    #      # ./zfs_disk.sh -z zroot "-o mountpoint=/db -o recordsize=8K zroot/db"
    zfs|-z)
        THIS_POOLNAME=$2
        THIS_ZFSCOMMAND=$3

        if [ -z "${THIS_POOLNAME}" ] || [ -z "${THIS_ZFSCOMMAND}" ]; then
            echo "missing argument"
            echo -e "${HELP_INFO}"
            exit 1
        fi
        echo "Begin zfs---" >> ${THIS_FILE}.log
        echo "\${THIS_POOLNAME} > ${THIS_POOLNAME}" >> ${THIS_FILE}.log
        echo "\${THIS_ZFSCOMMAND} > ${THIS_ZFSCOMMAND}" >> ${THIS_FILE}.log

        if [ "${THIS_ZFSCOMMAND}" = "auto" ]; then
            zfs create -o mountpoint=/tmp -o exec=on -o setuid=off "${THIS_POOLNAME}/tmp" >> ${THIS_FILE}.log 2>&1

            zfs create -o mountpoint=/usr -o canmount=off "${THIS_POOLNAME}/usr" >> ${THIS_FILE}.log 2>&1
            zfs create -o setuid=off "${THIS_POOLNAME}/usr/ports" >> ${THIS_FILE}.log 2>&1
            zfs create  "${THIS_POOLNAME}/usr/src" >> ${THIS_FILE}.log 2>&1

            zfs create -o mountpoint=/var -o canmount=off "${THIS_POOLNAME}/var" >> ${THIS_FILE}.log 2>&1
            zfs create -o exec=off -o setuid=off "${THIS_POOLNAME}/var/audit" >> ${THIS_FILE}.log 2>&1
            zfs create -o exec=off -o setuid=off "${THIS_POOLNAME}/var/crash" >> ${THIS_FILE}.log 2>&1
            zfs create -o exec=off -o setuid=off "${THIS_POOLNAME}/var/log" >> ${THIS_FILE}.log 2>&1
            zfs create -o atime=on "${THIS_POOLNAME}/var/mail" >> ${THIS_FILE}.log 2>&1
            zfs create -o setuid=off "${THIS_POOLNAME}/var/tmp" >> ${THIS_FILE}.log 2>&1

            zfs create -o mountpoint=/home "${THIS_POOLNAME}/home" >> ${THIS_FILE}.log 2>&1
        else
            zfs create ${THIS_ZFSCOMMAND} >> ${THIS_FILE}.log 2>&1
        fi

        echo "End zfs---" >> ${THIS_FILE}.log
        echo "create dataset successful..."
        ;;

    # finish: # ./zfs_disk.sh -f zroot
    finish|-f)
        THIS_POOLNAME=$2

        if [ -z "${THIS_POOLNAME}" ]; then
            echo "missing argument"
            echo -e "${HELP_INFO}"
            exit 1
        fi
        echo "Begin finish---" >> ${THIS_FILE}.log
        echo "\${THIS_POOLNAME} > ${THIS_POOLNAME}" >> ${THIS_FILE}.log

        zfs set "mountpoint=/${THIS_POOLNAME}" "${THIS_POOLNAME}" >> ${THIS_FILE}.log 2>&1
        chmod 1777 "/mnt/tmp" >> ${THIS_FILE}.log 2>&1
        chmod 1777 "/mnt/var/tmp" >> ${THIS_FILE}.log 2>&1

        zpool set bootfs="${THIS_POOLNAME}/ROOT/default" "${THIS_POOLNAME}" >> ${THIS_FILE}.log 2>&1
        zpool export "${THIS_POOLNAME}" >> ${THIS_FILE}.log 2>&1
        zpool import -o altroot="/mnt" "${THIS_POOLNAME}" >> ${THIS_FILE}.log 2>&1

        mkdir -p "/mnt/boot/zfs" >> ${THIS_FILE}.log 2>&1
        zpool set cachefile="/mnt/boot/zfs/zpool.cache" "${THIS_POOLNAME}" >> ${THIS_FILE}.log 2>&1
        echo "zfs_enable=\"YES\"" >> "/tmp/bsdinstall_etc/rc.conf.zfs"
        echo "kern.geom.label.gptid.enable=\"0\"" >> "/tmp/bsdinstall_boot/loader.conf.zfs"

        echo "End finish---" >> ${THIS_FILE}.log
        echo "finish successful..."
        ;;

    # help: # ./zfs_disk.sh -h
    help|-h)
        echo -e "${HELP_INFO}"
        exit 0
        ;;

    # info: # ./zfs_disk.sh -o
    #   or: # ./zfs_disk.sh -o da0
    info|-o)
        THIS_DEVICE=$2

        echo "Begin info---" >> ${THIS_FILE}.log
        echo "\${THIS_DEVICE} > ${THIS_DEVICE}" >> ${THIS_FILE}.log

        if [ -z "${THIS_DEVICE}" ]; then
            gpart show
        else
            gpart show "${THIS_DEVICE}"
        fi

        echo "End info---" >> ${THIS_FILE}.log
        echo "show disk info successful..."
        ;;

    # error
    *)
        echo "unrecognized command '${THIS_OPE}'"
        echo -e "${HELP_INFO}"
        exit 1
        ;;
esac
