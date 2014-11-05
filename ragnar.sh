#!/bin/sh
#
# Name: ragnar
# Auth: Gavin Lloyd <gavinhungry@gmail.com>
# Desc: Mount a remote LUKS device with NBD over SSH
#

source $(dirname "${BASH_SOURCE}")/abash/abash.sh

SERVER=${RAGNAR_SERVER:-subterfuge}
NBDEXPORT=${RAGNAR_NBDEXPORT:-ragnar}

TMPDIR=/tmp/.nbd-${SERVER}-${NBDEXPORT}
mkdir -p $TMPDIR

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
  [ -f "${TMPDIR}/ssh" ] && ps -p $(cat "${TMPDIR}/ssh") &> /dev/null
}

close_ssh() {
  if ssh_is_open; then
    kill $(cat "${TMPDIR}/ssh") && rm "${TMPDIR}/ssh"
  fi
}

export_is_open() {
  [ -f "${TMPDIR}/nbd" ] || return 1
  nbd_is_open $(cat "${TMPDIR}/nbd")
}

open() {
  export_is_open && err "${NBDEXPORT} already open on $(cat "${TMPDIR}/nbd")"

  msg "Opening SSH connection to $SERVER"
  close_ssh
  ssh -N -L 10809:127.0.0.1:10809 $SERVER &> /dev/null &
  echo $! > $TMPDIR/ssh

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
  echo CLOSE
  # unmount
  # luksClose
  # close NBD export
  # close_ssh
}

case $1 in
  'open') open ;;
  'close') close ;;
  *) usage '[open|close]' ;;
esac
