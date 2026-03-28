chroot_is_magisk_context() {
  local ctx
  ctx="$(chroot_selinux_context)"
  [[ "$ctx" == *":magisk:"* ]]
}

chroot_is_root_provider_context() {
  local ctx
  ctx="$(chroot_selinux_context)"
  [[ "$ctx" == *":magisk:"* || "$ctx" == *":kernelsu:"* || "$ctx" == *":apatch:"* || "$ctx" == *":su:"* ]]
}
