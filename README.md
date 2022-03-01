[ragnar](http://en.battlestarwiki.org/wiki/Ragnar_Anchorage)
========
Mount an existing remote [LUKS](https://gitlab.com/cryptsetup/cryptsetup) device
with [NBD](http://nbd.sourceforge.net/) over SSH. This has the advantage of
never exposing your LUKS keyfile to the server, as all encryption/decryption
takes place on your local machine.

You must have an existing LUKS device with a keyfile being exported by NBD on
some remote server. Your NBD server should be behind a firewall, and only listen
on `localhost`.

Environment Variables
---------------------
  - `RAGNAR_SERVER`: Server to connect to (can be a host alias from
    `~/.ssh/config`). Defaults to `localhost`.
  - `RAGNAR_NBDEXPORT`: Name of remote NBD export (see remote
    `/etc/nbd-server/config`). Defaults to `ragnar`.
  - `RAGNAR_KEYFILE`: Path to LUKS keyfile. Defaults to
    `/etc/luks/${RAGNAR_NBDEXPORT}.key`

Usage
-----

### Open

    $ ragnar open
    [sudo] password:

    ragnar: Opening SSH connection to localhost ...
    ragnar: Opening network block device on /dev/nbd0 ...
    ragnar: Opening LUKS device from /dev/nbd0 ...
    ragnar: Mounting filesystem from /dev/mapper/ragnar ...
    ragnar: Filesystem is mounted on /media/ragnar

### Close

    $ ragnar close
    [sudo] password:

    ragnar: Closing filesystem on /media/ragnar ...
    ragnar: Closing LUKS device from /dev/nbd0 ...
    ragnar: Closing network block device on /dev/nbd0 ...
    ragnar: Closing SSH connection to localhost ...

License
-------
This software is released under the terms of the **MIT license**. See `LICENSE`.
