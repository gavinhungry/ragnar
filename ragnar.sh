#!/bin/sh
#
# Name: ragnar
# Auth: Gavin Lloyd <gavinhungry@gmail.com>
# Desc: Mount a remote LUKS device with NBD over SSH
#

source $(dirname "${BASH_SOURCE}")/abash/abash.sh

SERVER=${RAGNAR_SERVER:-subterfuge}
NBDEXPORT=${RAGNAR_NBDEXPORT:-ragnar}
KEYFILE=${RAGNAR_KEYFILE}

TMPDIR=/tmp/.nbd-${SERVER}-${NBDEXPORT}
mkdir -p $TMPDIR

nbd_device() {
  cat "${TMPDIR}/nbd"
}

ssh_pid() {
  cat "${TMPDIR}/ssh"
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

ssh_is_open() {
  [ -f "${TMPDIR}/ssh" ] && ps -p $(ssh_pid) &> /dev/null
}

close_ssh() {
  if ssh_is_open; then
    kill -9 $(ssh_pid) &> /dev/null && rm "${TMPDIR}/ssh"
  fi
}

export_is_open() {
  [ -f "${TMPDIR}/nbd" ] || return 1
  nbd_is_open $(nbd_device)
}

close_export() {
  if export_is_open; then
    sudo -v
    sudo modprobe nbd
    sudo nbd-client -d /dev/$(nbd_device) &> /dev/null
  fi
}

open() {
  export_is_open && die "${NBDEXPORT} already open on $(nbd_device)"

  msg "Opening SSH connection to ${SERVER}"
  close_ssh || die "Could not close existing SSH connection to ${SERVER}"
  ssh -NnL 10809:127.0.0.1:10809 $SERVER &> /dev/null &
  SSH_PID=$!
  disown $SSH_PID
  echo $SSH_PID > $TMPDIR/ssh
  sleep 1

  NBD=$(nbd_next_open)

  msg "Opening network block device on ${NBD}"
  sudo -v
  sudo modprobe nbd

  if sudo nbd-client localhost /dev/$NBD -name $NBDEXPORT &> /dev/null; then
    echo $NBD > $TMPDIR/nbd
    msg "time to luksOpen, then mount"
  else
    close_ssh
    rm -fr $TMPDIR
    err "Error opening network block device"
  fi
}

close() {
  # unmount
  # luksClose

  export_is_open && msg "Closing network block device on $(nbd_device)"
  close_export

  ssh_is_open && msg "Closing SSH connection to ${SERVER}"
  close_ssh
}

# [ -z "$KEYFILE" ] && die "RAGNAR_KEYFILE must be specified"

case $1 in
  'open') open ;;
  'close') close ;;
  *) usage '[open|close]' ;;
esac
