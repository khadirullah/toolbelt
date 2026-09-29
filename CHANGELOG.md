# Changelog

## 0.1.0

The first release, with 70 commands in eight groups.

- Archives: unpack, squash, archdiff, archmount, autounpack.
- Files: bak, checksum, bulkrename, fixperms, dupes, bigfiles, recent, mirror, lock, unlock, shrink, togif.
- System: pkg, mem, cleanup, sysinfo, proc, svc, logs, disks, boottime, temps, seccheck, schedules.
- Network: port, myip, netcheck, waitfor, share, lan, httptime, sshfwd, speed.
- Everyday: again, notify-done, cheats, clip, genpass, timer, note, epoch.
- Kubernetes: kwhy, ksecret, kyaml, kclean, kfwd, kres, knodes, kevents.
- DevOps: ctx, certcheck, dnscheck, tfcheck, yamlcheck, imgpeek, jwtpeek, git undo, git prune-merged, git recent,
  git wip, git sync, git whoami.
- Shell: mkcd, up, and toolbelt with help, doctor, setup, shell, update, version, uninstall and new.

Every command has `--help`, a man page, bash and zsh completion, and tests that CI runs on Debian 13, Ubuntu 24.04,
Ubuntu 22.04, Fedora 44, Rocky Linux 9, Arch Linux, openSUSE Leap 15 and Alpine 3.
