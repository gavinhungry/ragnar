#!/bin/sh
#
# Name: ragnar
# Auth: Gavin Lloyd <gavinhungry@gmail.com>
# Desc: Mount a remote LUKS device with NBD over SSH
#

source $(dirname "${BASH_SOURCE}")/abash/abash.sh

SERVER=${RAGNAR_SERVER:-subterfuge}
NBDEXPORT=${RAGNAR_NBDEXPORT:-ragnar}
KEYFILE=${RAGNAR_KEYFILE:-/etc/luks/${NBDEXPORT}.key}

TMPDIR=/tmp/.nbd-${SERVER}-${NBDEXPORT}
mkdir -p ${TMPDIR}

ssh_pid() {
  cat "${TMPDIR}/ssh"
}

ssh_is_open() {
  [ -f "${TMPDIR}/ssh" ] && ps -p $(ssh_pid) &> /dev/null
}

open_ssh() {
  ssh -NnL 10809:127.0.0.1:10809 $SERVER &> /dev/null &
  SSH_PID=$!
  disown $SSH_PID
  echo $SSH_PID > ${TMPDIR}/ssh
}

close_ssh() {
  if ssh_is_open; then
    kill -9 $(ssh_pid) &> /dev/null && rm "${TMPDIR}/ssh"
  fi
}

nbd_device() {
  cat "${TMPDIR}/nbd"
}

nbd_is_open() {
  [ -f "/sys/block/${1}/pid" ]
}

nbd_next_open() {
  for DEV in /dev/nbd*; do
    NBD=$(echo $DEV | cut -d'/' -f3)
    if ! nbd_is_open $NBD; then
      echo $NBD
      return
    fi
  done
}

export_is_open() {
  [ -f "${TMPDIR}/nbd" ] || return 1
  nbd_is_open $(nbd_device)
}

open_export() {
  sudo -v
  sudo modprobe nbd
  NBD=$1

  if sudo nbd-client localhost /dev/$NBD -name $NBDEXPORT &> /dev/null; then
    echo $NBD > ${TMPDIR}/nbd
    msg "time to luksOpen, then mount"
  else
    close_ssh
    rm -fr ${TMPDIR}
    return 1
  fi
}

close_export() {
  if export_is_open; then
    sudo -v
    sudo modprobe nbd
    sudo nbd-client -d /dev/$(nbd_device) &> /dev/null && rm -f "${TMPDIR}/nbd"
  fi
}

luks_is_open() {
  echo LUKS_IS_OPEN
}

luks_open() {
  echo cryptsetup luksOpen
}

luks_close() {
  echo cryptsetup luksClose
}

open() {
  export_is_open && die "${NBDEXPORT} already open on $(nbd_device)"

  msg "Opening SSH connection to ${SERVER}"
  close_ssh || die "Could not close existing SSH connection to ${SERVER}"
  open_ssh
  sleep 1

  NBD=$(nbd_next_open)
  msg "Opening network block device on ${NBD}"
  open_export $NBD || dir "Could not open network block device on ${NBD}"
}

close() {
  # unmount
  # luksClose

  export_is_open && msg "Closing network block device on $(nbd_device)"
  close_export || die "Could not close network block device on $(nbd_device)"

  ssh_is_open && msg "Closing SSH connection to ${SERVER}"
  close_ssh || die "Could not close existing SSH connection to ${SERVER}"

  rm -fr ${TMPDIR}
}

sudo [ -f "${KEYFILE}" ] || die "Keyfile not found"

case $1 in
  'open') open ;;
  'close') close ;;
  *) usage '[open|close]' ;;
esac
