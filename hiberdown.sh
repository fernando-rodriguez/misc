#!/bin/bash
#
# fastdown script v0.1
# Copyright (C) 2014 Fernando Rodriguez (frodriguez.developer@outlook.com)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License Version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

source /etc/hiberdown.conf

plymouth_start_daemon()
{
  /usr/bin/plymouth --ping && /usr/bin/plymouth change-mode --shutdown ||
    /sbin/plymouthd --mode=shutdown --kernel-command-line="splash"
}

plymouth_set_boot_mode()
{
  /usr/bin/plymouth change-mode --boot-up
}

plymouth_set_message()
{
  #/usr/bin/plymouth display-message --text=msg
  #/usr/bin/plymouth display-message --text="$1"
  /usr/bin/plymouth update --status=msg
  /usr/bin/plymouth update --status="$1"
}

plymouth_show_splash()
{
  /usr/bin/plymouth --show-splash
}

plymouth_show_progress()
{
  /usr/bin/plymouth display-message --text=show-progress
}

plymouth_hide_progress()
{
  /usr/bin/plymouth display-message --text=hide-progress
}

# kill processes started
# from ttys
#
kill_tty_processes()
{
  procs_arr=$(/bin/cat /sys/fs/cgroup/openrc/ttys/tasks)

  for proc in $procs_arr
  do
    /bin/kill $proc
  done

  for proc in $procs_arr
  do
    /bin/kill -9 $proc
  done
}

# restore all services to their propper boot up state.
#
restore_runlevel_services()
{
  # prepare list of all openrc services, their states and a list
  # list of services in the sysinit, boot, and default runlevels
  #
  found=0
  svcs_arr=(`/bin/rc-status --all | /bin/grep "\[" | /bin/sed "s/\[//;s/\]//;s/ *//" | /bin/tr -s " "`)
  svcs_len=${#svcs_arr[@]}
  svcs_len=$(((svcs_len) / 2))
  svcs_preserve=$(/bin/echo $preserved_services)
  runlevel_svcs=$(/bin/ls /etc/runlevels/sysinit /etc/runlevels/boot /etc/runlevels/default)

  # loop through the list of processes and make sure that every process
  # is on the same state as right after boot up
  #
  for ((i=0; i<$svcs_len; i++))
  do
    found=0
    for svc in $runlevel_svcs
    do
      if [ "${svcs_arr[$((i * 2))]}" == "$svc" ]; then
        found=1
        if [ "${svcs_arr[$(((i * 2) + 1))]}" != "started" ]; then
          /sbin/rc-service $svc cgroup_cleanup
          /sbin/rc-service $svc start
        fi
      fi
    done
    if [ $found == 0 ]; then
      if [ "${svcs_arr[$(((i * 2) + 1))]}" == "started" ]; then
        for psvd_svc in $svcs_preserve
        do
          if [ "${svcs_arr[$((i * 2))]}" == "$psvd_svc" ]; then
            found=1
          fi
        done
        if [ $found == 0 ]; then
          /sbin/rc-service ${svcs_arr[$((i * 2))]} stop
          /sbin/rc-service ${svcs_arr[$((i * 2))]} cgroup_cleanup
        fi
      fi
    fi
  done
}

quiet=0
splash=0
bootmode=$1
swsusp_resume=""

case "$bootmode" in
  shutdown) shift;;
  kde|poweroff) shift;;
  kde-nohup|poweroff-daemon) shift;;
  init) shift;;
  boot) shift;;
  hibernate-hook) shift;;
  suspend-hook) shift;;

  # todo: make sure this is pid 1
  #
  *) bootmode="boot" ;;
esac

if [ "$bootmode" == "boot" ]; then
  /bin/mount -o remount,ro / >/dev/null 2>&1
  /bin/mount -t proc -o noexec,nosuid,nodev proc /proc >/dev/null 2>&1
  /bin/mount -t sysfs -o rw,nosuid,relatime,mode=755 none /sys 2>&1
fi

# parse the command line
#
for arg in $(/bin/cat /proc/cmdline);
do
  case "${arg}" in
    quiet)
      quiet=1
      ;;
    splash)
      splash=1
      ;;
    swsusp_resume=*)
      swsusp_resume=${arg#*=}
      #swsusp_resume=$(readlink -f ${swsusp_resume} | awk -F '/' '{ print $3 }')
      #swsusp_resume=$(cat /sys/class/block/${swsusp_resume}/dev)
      ;;
  esac
done

case $bootmode in
  boot)
    # start plymouth and show splash if booting with the
    # splash and quiet options
    #
    if [ $splash == 1 ]; then
      plymouth_start_daemon
      plymouth_show_splash
    fi

    # Resume using swsusp
    #
    if [ "$swsusp_resume" != "" ]; then

      plymouth_set_message "Thawing System..."

      /bin/sync
      echo "$swsusp_resume" > /sys/power/resume

      plymouth_set_boot_mode
      plymouth_show_progress
      plymouth_set_message "Booting System..."

    else
      plymouth_set_boot_mode
      plymouth_show_progress
      plymouth_set_message "Booting System..."
    fi

    exec /sbin/init
    ;;

  init)

    # create a cgroup for all processes
    # started from tty logins
    #
    /usr/bin/cgcreate -g "name=openrc":/ttys

    # hide the blinking cursor in all terminals except the
    # ones with logins
    #
    for tty in $(/bin/echo $free_ttys)
    do
      /bin/echo -e '\033[?17;0;0c' > /dev/$tty
    done
    ;;

  shutdown)
    # start plymouth and show splash if booting with the
    # splash and quiet options
    #
    if [ $splash == 1 ]; then
      plymouth_start_daemon
      plymouth_show_progress
      plymouth_show_splash
      plymouth_set_message "Shutting down..."
    fi
    $@
    ;;

  hibernate-hook)
    plymouth_start_daemon
    plymouth_hide_progress
    plymouth_set_message "Hibernating System..."
    plymouth_show_splash
    /bin/sync
    ;;

  suspend-hook)
    plymouth_start_daemon
    plymouth_hide_progress
    plymouth_set_message "Suspending System..."
    plymouth_show_splash
    /bin/sync
    ;;

  poweroff)
    [ -d /sys/fs/openrc/free ] || /usr/bin/cgcreate -g "name=openrc":/free
    /usr/bin/cgexec -g "name=openrc":/free $(realpath ${BASH_SOURCE[0]}) poweroff-daemon
    ;;

  poweroff-daemon)
    # start splash screen
    #
    if [ $splash == 1 ]; then
      plymouth_start_daemon
      plymouth_show_splash
    fi
    
    # kill all processes in TTY logins
    #
    plymouth_set_message "Killing TTY processes..."
    kill_tty_processes

    # stop the xdm service and kill all processes
    # in it's group
    #
    plymouth_set_message "Killing user processes..."
    /sbin/rc-service xdm stop
    /sbin/rc-service xdm cgroup_cleanup

    # restart all default runlevel services
    #
    plymouth_set_message "Restoring default runlevel services..."
    restore_runlevel_services
    
    # restart kdm
    #
    plymouth_set_message "Restarting KDM..."
    /sbin/rc-service xdm restart 
    /usr/bin/sleep $dm_restart_time

    # hibernate system
    #
    /usr/sbin/pm-hibernate
    ;;
esac

