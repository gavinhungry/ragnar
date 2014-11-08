#!/bin/sh
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

TMPDIR=/tmp/.nbd-${SERVER}-${NBDEXPORT}
mkdir -p ${TMPDIR}

ssh_pid() {
  cat "${TMPDIR}/ssh" 2> /dev/null
}

ssh_is_open() {
  [ -f "${TMPDIR}/ssh" ] && ps -p $(ssh_pid) &> /dev/null
}

open_ssh() {
  ssh -NnL 10809:127.0.0.1:10809 ${SERVER} &> /dev/null &
  SSH_PID=$!
  disown ${SSH_PID}
  echo ${SSH_PID} > ${TMPDIR}/ssh
}

close_ssh() {
  if ssh_is_open; then
    kill -9 $(ssh_pid) &> /dev/null && rm "${TMPDIR}/ssh"
  fi
}

nbd_device() {
  cat "${TMPDIR}/nbd" 2> /dev/null
}

nbd_is_open() {
  [ -f "/sys/block/${1}/pid" ]
}

nbd_next_open() {
  for DEV in /dev/nbd*; do
    NBD=$(echo ${DEV} | cut -d'/' -f3)
    if ! nbd_is_open ${NBD}; then
      echo ${NBD}
      return
    fi
  done
}

export_is_open() {
  [ -f "${TMPDIR}/nbd" ] || return 1
  nbd_is_open $(nbd_device)
}

open_export() {
  checksu modprobe nbd
  NBD=$1

  if checksu nbd-client localhost /dev/${NBD} -name ${NBDEXPORT} &> /dev/null; then
    echo ${NBD} > ${TMPDIR}/nbd
  else
    close_ssh
    rm -fr ${TMPDIR}
    return 1
  fi
}

close_export() {
  if export_is_open; then
    checksu
    checksu modprobe nbd
    checksu nbd-client -d /dev/$(nbd_device) &> /dev/null && rm -f "${TMPDIR}/nbd"
  fi
}

luks_is_open() {
  [ -b /dev/mapper/${NBDEXPORT} ]
}

luks_open() {
  checksu cryptsetup luksOpen /dev/$(nbd_device) ${NBDEXPORT} -d ${KEYFILE}
}

luks_close() {
  checksu cryptsetup luksClose /dev/mapper/${NBDEXPORT}
}

filesystem_is_mounted() {
  mountpoint /media/${NBDEXPORT} &> /dev/null
}

mount_filesystem() {
  checksu udisks --mount /dev/mapper/${NBDEXPORT} &> /dev/null
}

unmount_filesystem() {
  checksu udisks --unmount /dev/mapper/${NBDEXPORT} &> /dev/null
}

open() {
  export_is_open && die "${NBDEXPORT} already open on $(nbd_device)"
  checksu [ -f "${KEYFILE}" ] || die "Keyfile not found"

  msg "Opening SSH connection to ${SERVER}"
  open_ssh || die "Could not open SSH connection to ${SERVER}"
  sleep 1

  NBD=$(nbd_next_open)
  msg "Opening network block device on /dev/${NBD}"
  open_export ${NBD} || die "Could not open network block device on /dev/${NBD}"

  msg "Opening LUKS device from /dev/${NBD}"
  luks_open || die "Could not open LUKS device from /dev/${NBD}"

  msg "Mounting filesystem on /media/${NBDEXPORT}"
  mount_filesystem || die "Could not mount filesystem on /media/${NBDEXPORT}"
}

close() {
  export_is_open || die "${NBDEXPORT} is not open"
  NBD=$(nbd_device)

  filesystem_is_mounted && msg "Closing filesystem on /media/${NBDEXPORT}"
  unmount_filesystem || die "Could not close filesystem on /media/${NBDEXPORT}"

  luks_is_open && msg "Closing LUKS device from /dev/${NBD}"
  luks_close || die "Could not close LUKS device from /dev/${NBD}"

  export_is_open && msg "Closing network block device on /dev/${NBD}"
  close_export || die "Could not close network block device on /dev/${NBD}"

  ssh_is_open && msg "Closing SSH connection to ${SERVER}"
  close_ssh || die "Could not close existing SSH connection to ${SERVER}"

  rm -fr ${TMPDIR}
}

case $1 in
  'open') open ;;
  'close') close ;;
  *) usage '[open|close]' ;;
esac
