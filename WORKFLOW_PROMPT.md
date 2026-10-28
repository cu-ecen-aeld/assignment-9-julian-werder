# Assignment 9: llseek and AESDCHAR_IOCSEEKTO in aesdchar, seek command in aesdsocket

This one is split into two runs because I have to push in between. Run 1 adds seek and the ioctl to the driver
and the seek command to aesdsocket, and tests them in QEMU. Run 2 bumps the Buildroot package and runs the full
test.

The hard rules (no pushing, commit message style, one QEMU at a time, how to wait on builds) are in
`~/AESD/.claude/PROJECT.md`. I'm not repeating them here. When you hand work to someone, point them at the
section of this file they own instead of copying it into their prompt.

## Where things are right now
I checked all of this on 2026-10-27, so you don't need to survey it again.

- Everything runs in WSL under `~/AESD`. Get my GitHub username with `gh api user -q .login`. gh is logged in and
  git uses the WSL ssh key.
- WSL has a global git identity, so a plain `git commit` works. Don't add `git -c` workarounds.
- Don't try to build or load kernel modules on the host. WSL has no kernel headers. All driver testing is in QEMU.
- A3 repo (`~/AESD/assignment-3-<username>`) is set up and clean. The assignment9 base is merged (`b47bd5c`),
  submodules are updated (autotest stays at `a421651`, which already has the assignment9 tests) and
  `conf/assignment.txt` is `assignment9`. The merge only added `aesd-char-driver/aesd_ioctl.h`
  (don't edit it). It defines `struct aesd_seekto` (`uint32_t write_cmd`,
  `uint32_t write_cmd_offset`), `AESD_IOC_MAGIC 0x16`, `AESDCHAR_IOCSEEKTO _IOWR(AESD_IOC_MAGIC, 1, struct
  aesd_seekto)` and `AESDCHAR_IOC_MAXNR 1`. It includes `<asm-generic/ioctl.h>` in the kernel and `<sys/ioctl.h>`
  and `<stdint.h>` in user space.
- The A8 driver (`aesd-char-driver/main.c`, 196 lines) has open, release, read and write. read returns at most
  one entry per call and uses `aesd_circular_buffer_find_entry_offset_for_fpos()`. write ignores offsets.
  `struct aesd_dev` in `aesdchar.h` has `buffer`, `partial` (the write without a newline yet), `lock` (a mutex)
  and `cdev`. The circular buffer has `entry[]`, `in_offs`, `out_offs` and `full`, with
  `AESDCHAR_MAX_WRITE_OPERATIONS_SUPPORTED` = 10.
- `server/aesdsocket.c` (942 lines) is built with `USE_AESD_CHAR_DEVICE` = 1 by default, so `DATA_FILE` is
  `/dev/aesdchar`. `process_packet()` takes `data_mutex`, calls `append_packet()` (open, write, close) and then
  `send_data_file()` (open, read and send, close). Each packet it gets still ends in its `'\n'`. Style rules for
  this file are in PROJECT.md.
- The A5 folder (`~/AESD/assignment-5-<username>`) is my working copy for A9 and it's set up and clean. origin is
  `cu-ecen-aeld/assignment-9-<username>` (empty on GitHub until I push), the A8 repo remote is now
  `assignment-8-remote`, the buildroot assignment9 base is merged (`2dd4fb0`, submodules updated) and
  `conf/assignment.txt` is `assignment9-buildroot`. The workflow still uses the `24-assignment7-buildroot`
  container. Leave that alone.
- That folder already has a full build (`buildroot/output`, 14G), so builds are incremental. Don't clone it
  somewhere else and don't move it. `aesd-assignments.mk` already uses kernel-module infra
  (`AESD_ASSIGNMENTS_MODULE_SUBDIRS = aesd-char-driver`), installs `S97aesdchar` and `S99aesdsocket`, and has
  `AESD_ASSIGNMENTS_VERSION = 000194d3e6fe18909eb33660b629c34b7158572b` (the A8 commit).
- What you can use to test Run 1 (`<A5>` is the A5 folder):
  - kernel tree: `<A5>/buildroot/output/build/linux-6.18.7` (has `.config` and `Module.symvers`)
  - cross compiler: `<A5>/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc`
  - the current image boots with the A8 driver loaded by `S97aesdchar` and A8 aesdsocket running. Log in with
    `sshpass -p root ssh -p 10022 root@localhost` (scp uses `-P 10022`).
- How it gets graded (`assignment-autotest/test/assignment9-buildroot/`): `validate_driver_assignment9` and
  `validate_application_assignment9` just call the assignment 8 ones. So `aesdchar` has to be in `lsmod` after
  boot, and the grader does `rmmod aesdchar` + `modprobe aesdchar` before drivertest and again before sockettest.
  That means aesdsocket still can't hold `/dev/aesdchar` open while it's idle.
  - `drivertest.sh` from that folder gets copied to `/usr/bin` in QEMU. It reads with
    `dd if=/dev/aesdchar skip=<n> bs=1`, so it needs llseek. The `assignment9/` (native) copy is different, so
    use the `assignment9-buildroot/` one.
  - `sockettest.sh` from that folder runs from the host on port 9000. It needs an empty device at the start,
    sends `swrite1` to `swrite10`, then `AESDCHAR_IOCSEEKTO:0,2` and expects `rite1` followed by `swrite2` to
    `swrite10`, then `AESDCHAR_IOCSEEKTO:8,6` and expects `9` and `swrite10`.
- The handout says writes of "5, 7, and 9 bytes" cover positions 0-5, 6-13 and 14-23. It's really 6, 8 and 10
  bytes, because each write includes its newline. That matches its own example (offset 15 is the "i" in
  "Singapore").

---

# Run 1: driver and aesdsocket in the A3 repo, tested in QEMU (hierarchy)

## How to split it up
- Keep it flat. Director sends work straight to workers, no manager. Skip the intake survey, the stuff above is
  already checked.
- R1-1 and R1-2 can run at the same time since they're in different folders. Then R1-3, then R1-4. Only R1-4
  touches QEMU.
- None of this takes more than a few minutes. Please don't add host build checks or extra stop conditions unless
  you have an actual reason.

## R1-1: the driver (worker, only `aesd-char-driver/`, don't touch `aesd_ioctl.h`)
I already decided how this should work, just implement it:
- `#include "aesd_ioctl.h"` in `main.c`.
- llseek (`.llseek = aesd_llseek`): take the lock with `mutex_lock_interruptible` (`-ERESTARTSYS`), add up the
  size of every entry in the buffer (`AESD_CIRCULAR_BUFFER_FOREACH`, partial doesn't count), unlock, and return
  `fixed_size_llseek(filp, off, whence, total)`. That handles SEEK_SET, SEEK_CUR and SEEK_END and returns
  `-EINVAL` for a position below 0 or past the end.
- ioctl (`.unlocked_ioctl = aesd_unlocked_ioctl`, returns `long`):
  - Return `-ENOTTY` if `_IOC_TYPE(cmd) != AESD_IOC_MAGIC` or `_IOC_NR(cmd) > AESDCHAR_IOC_MAXNR`, and for any cmd
    other than `AESDCHAR_IOCSEEKTO`.
  - `copy_from_user` a `struct aesd_seekto` (`-EFAULT`).
  - Under the lock: stored count is `AESDCHAR_MAX_WRITE_OPERATIONS_SUPPORTED` if `full`, else
    `(in_offs - out_offs + MAX) % MAX`. Return `-EINVAL` if `write_cmd >= count` or `write_cmd_offset` is
    `>=` the size of entry `(out_offs + write_cmd) % MAX`.
  - Otherwise the new position is the sizes of the `write_cmd` entries before it (starting at `out_offs`) plus
    `write_cmd_offset`. Set `filp->f_pos` to it, unlock and return 0.
- Keep read and write the way they are. Match the style that's already in the file. Max line length 120.
- It has to cross-build with zero warnings (this is one command):
  `make -C aesd-char-driver KERNELDIR=<A5>/buildroot/output/build/linux-6.18.7 ARCH=arm64`
  `CROSS_COMPILE=<A5>/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-`

## R1-2: aesdsocket (worker, only `server/`)
I already decided how this should work, just implement it:
- Only when `USE_AESD_CHAR_DEVICE` is on. When it's off, the seek string is just a normal packet, and nothing
  else changes.
- Include `"../aesd-char-driver/aesd_ioctl.h"` (inside the `#if`, after the system includes).
- A packet is a seek command if it's exactly `AESDCHAR_IOCSEEKTO:X,Y` plus its `'\n'`, where X and Y are only
  decimal digits (no sign or spaces) and each fits in a `uint32_t`. Parse it with `strtoul` and check the end
  pointers. Anything else is a normal packet.
- Seek command, inside `process_packet()` under `data_mutex`: open `DATA_FILE` `O_RDWR`, do
  `ioctl(fd, AESDCHAR_IOCSEEKTO, &seekto)`, then read from that same fd until it returns 0 and send it all over
  the socket. Close the fd. Don't write the command string to the device. If the ioctl fails, syslog it, close
  the fd and send nothing.
- Normal packets stay as they are. Pull the read-and-send loop out of `send_data_file()` into a helper that takes
  an fd, so both paths use it. The fd is still never held open while idle.
- Update the comment at the top of the file and the doc comments of anything you change.
- It has to build with zero warnings both ways, with the normal build and with the Yocto-like flags in PROJECT.md.
  `make -C server USE_AESD_CHAR_DEVICE=0` still has to pass the standalone socket test from PROJECT.md.

## R1-3: review (worker, read only)
Go through the R1-1 and R1-2 changes line by line against their lists. Check every path unlocks, the ioctl
bounds checks can't index past the buffer, `f_pos` is set under the lock, the seek parse rejects bad input
without overflow, and the seek path reads from the same fd it sent the ioctl on and closes it on every path.
Just report what you find. The Director decides what gets fixed, and there's only one fix round.

## R1-4: test in QEMU and commit (worker)
1. Do the QEMU and port checks from PROJECT.md. Boot the A5 image with the `./runqemu.sh` command plus
   `-snapshot`, detached and logging to a file (same ports, 10022 and 9000).
2. Cross-build aesdsocket with `make -C server CC=<A5>/buildroot/output/host/bin/aarch64-buildroot-linux-gnu-gcc`.
   Copy `aesdchar.ko`, `aesdchar_load`, `aesdchar_unload`, the aesdsocket binary and
   `assignment-autotest/test/assignment9-buildroot/drivertest.sh` into `/tmp` on the target.
3. In QEMU: `/etc/init.d/S99aesdsocket stop`, `rmmod aesdchar`, then `/tmp/aesdchar_load` (it picks up the local
   .ko). Run `/tmp/drivertest.sh`. It has to exit 0.
4. `rmmod aesdchar`, `/tmp/aesdchar_load` again (sockettest needs an empty device), start `/tmp/aesdsocket -d`,
   then run `assignment-autotest/test/assignment9-buildroot/sockettest.sh` from the host. It has to exit 0 and
   print "Test passed".
5. With aesdsocket still running and idle, `rmmod aesdchar` has to work.
6. Shut QEMU down, make sure it's gone, and `make clean` the build output out of the A3 tree.
7. Commit in the A3 repo: "assignment 9 complete: llseek and AESDCHAR_IOCSEEKTO in aesdchar, seek command in
   aesdsocket".

## When Run 1 is done
Give me the commit hash, the drivertest and sockettest output, and what the review found and what got fixed.
Then stop. I push the A3 repo before Run 2.

---

# Run 2: Buildroot in the A5 folder (solo, no hierarchy)

Before this starts I'll have pushed the A3 repo.

1. Check the Run 1 commit is on GitHub:
   `gh api repos/cu-ecen-aeld/assignment-3-<username>/commits/<hash> >/dev/null 2>&1; echo $?` has to print 0.
   If it doesn't, stop and tell me.
2. In `base_external/package/aesd-assignments/aesd-assignments.mk`, set `AESD_ASSIGNMENTS_VERSION` to the full
   Run 1 hash and change the comment above it to say it's the assignment 9 commit. Leave everything else alone.
3. Run `./build.sh`. It's incremental. Start it detached with a log and an exit code marker, and wait with bounded
   waits. The exit code has to be 0.
4. Run `./full-test.sh` (it builds, boots QEMU and runs the grader). It has to end with "complete with success"
   and no validation errors. If it fails, report it, don't keep retrying. You can fix it once if it's clearly
   something in the `.mk` change.
5. Commit using the course message style, something like "assignment 9 complete: build aesdchar with seek and
   ioctl in buildroot". Don't commit `WORKFLOW_PROMPT.md`.

## When Run 2 is done
Give me the commit hash, the `full-test.sh` summary and which files changed.

---

## Stuff I do myself
- After Run 1: push the A3 repo.
- After Run 2: push the A5 folder's `main` to `origin` (the A9 repo) with `git push -u origin main`. Tag
  `assignment-9-complete` in the A3 and A9 repos and push the tags.
