#!/usr/bin/env bash

chroot_cmd_init() {
  [[ $# -eq 0 ]] || chroot_die "usage: bash path/to/chroot init"
  chroot_init_text
}
