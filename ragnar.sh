#!/bin/bash
#
# Name: ragnar
# Auth: Gavin Lloyd <gavinhungry@gmail.com>
# Desc: Mount an existing remote LUKS device with NBD over SSH
#
# Released under the terms of the MIT license
# https://github.com/gavinhungry/ragnar
#

[ ${_ABASH:-0} -ne 0 ] || source $(dirname "${BASH_SOURCE}")/abash/abash.sh

SERVER=${RAGNAR_SERVER:-localhost}
NBDEXPORT=${RAGNAR_NBDEXPORT:-ragnar}
KEYFILE=${RAGNAR_KEYFILE:-/etc/luks/${NBDEXPORT}.key}
HEADER=${RAGNAR_HEADER:-/etc/luks/${NBDEXPORT}.header}

TMP=$(tmpdirp "${SERVER}-${NBDEXPORT}")
mkdir -p ${TMP}

ssh_is_open() {
  ssh -qO check -S "${TMP}/ssh" ${SERVER} &> /dev/null
}

open_ssh() {
  ssh -fNn -MS "${TMP}/ssh" -L 10809:127.0.0.1:10809 ${SERVER}
}

close_ssh() {
  if ssh_is_open; then
    ssh -qO exit -S "${TMP}/ssh" ${SERVER}
  fi
}

nbd_device() {
  cat "${TMP}/nbd" 2> /dev/null
}

nbd_is_open() {
  [ -f "/sys/block/${1}/pid" ]
}

nbd_next_open() {
  checksu modprobe nbd

  for DEV in /dev/nbd*; do
    NBD=$(echo ${DEV} | cut -d'/' -f3)
    if ! nbd_is_open ${NBD}; then
      echo ${NBD}
      return
    fi
  done
}

export_is_open() {
  [ -f "${TMP}/nbd" ] || return 1
  nbd_is_open $(nbd_device)
}

open_export() {
  checksu modprobe nbd
  NBD=$1

  if quietly checksu nbd-client 127.0.0.1 /dev/${NBD} -name ${NBDEXPORT}; then
    echo ${NBD} > ${TMP}/nbd
  else
    close_ssh
    rm -fr ${TMP}
    return 1
  fi
}

close_export() {
  if export_is_open; then
    checksu
    checksu modprobe nbd
    quietly checksu nbd-client -d /dev/$(nbd_device) && quietly rm -f "${TMP}/nbd"
  fi
}

luks_is_open() {
  [ -b /dev/mapper/${NBDEXPORT} ]
}

luks_open() {
  NBD=$1
  checksu [ -f ${HEADER} ] || HEADER=${NBD}
  checksu cryptsetup luksOpen /dev/${NBD} ${NBDEXPORT} -d ${KEYFILE} --header ${HEADER}
}

luks_close() {
  checksu cryptsetup luksClose /dev/mapper/${NBDEXPORT}
}

filesystem_mountpoint() {
  udisksctl info -b /dev/mapper/${NBDEXPORT} 2> /dev/null | grep MountPoints | cut -d':' -f2 | sed 's/^\s*//'
}

filesystem_is_mounted() {
  [ -n "$(filesystem_mountpoint)" ]
}

mount_filesystem() {
  quietly checksu udisksctl mount -b /dev/mapper/${NBDEXPORT}
}

unmount_filesystem() {
  quietly checksu udisksctl unmount -b /dev/mapper/${NBDEXPORT}
}

open() {
  export_is_open && die "${NBDEXPORT} already open on $(nbd_device)"
  checksu [ -f "${KEYFILE}" ] || die "Keyfile not found"

  inform "Opening SSH connection to ${SERVER}"
  open_ssh || die "Could not open SSH connection to ${SERVER}"
  sleep 1

  NBD=$(nbd_next_open)
  inform "Opening network block device on /dev/${NBD}"
  open_export ${NBD} || die "Could not open network block device on /dev/${NBD}"

  inform "Opening LUKS device from /dev/${NBD}"
  luks_open ${NBD} || die "Could not open LUKS device from /dev/${NBD}"

  inform "Mounting filesystem from /dev/mapper/${NBDEXPORT}"
  mount_filesystem || die "Could not mount filesystem from /dev/mapper/${NBDEXPORT}"

  msg "Filesystem is mounted on $(filesystem_mountpoint)"
}

close() {
  export_is_open || die "${NBDEXPORT} is not open"
  NBD=$(nbd_device)

  checksu

  MOUNTPOINT=$(filesystem_mountpoint)

  filesystem_is_mounted && inform "Closing filesystem on ${MOUNTPOINT}"
  unmount_filesystem || die "Could not close filesystem on ${MOUNTPOINT}"

  luks_is_open && inform "Closing LUKS device from /dev/${NBD}"
  luks_close || die "Could not close LUKS device from /dev/${NBD}"

  export_is_open && inform "Closing network block device on /dev/${NBD}"
  close_export || die "Could not close network block device on /dev/${NBD}"

  ssh_is_open && inform "Closing SSH connection to ${SERVER}"
  close_ssh || die "Could not close existing SSH connection to ${SERVER}"

  tmpdirclean
}

case $1 in
  'open') open ;;
  'close') close ;;
  *) usage '[open|close]' ;;
esac
