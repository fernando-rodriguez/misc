/*
 * Copyright (C) 2015 Fernando Rodriguez (frodriguez.developer@outlook.com)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License Version 2 as 
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * 
 * *******************************************
 *
 * This is a small program that is executed when an ssh session
 * start by specifying it as the ForceCommand option on sshd_config.
 *
 * It removes the client ip from the xt_recent list specified at 
 * compile time and then executes the ssh command specified by the
 * client or the user shell.
 *
 * It must have the setuid bit set in order to be able to remove
 * the ip from the xt_recent list but it will drop the suid privilege
 * before executing the command or shell.
 *
 * To compile simply run:
 * 
 * gcc -DRECENT_LIST=ssh_bad ssh-cmdexec.c -o ssh-cmdexec
 *
 * Where ssh_bad is the name of the xt_recent list. If no
 * -DRECENT_LIST=<list_name> is not specified DEFAULT is
 * assumed.
 *
 */

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <string.h>

#ifndef RECENT_LIST
#define RECENT_LIST DEFAULT
#endif

#ifndef DEFAULT_SHELL
#define DEFAULT_SHELL "/bin/bash"
#endif

#define STRINGIZE(x) #x
#define STRINGIZE_RECENT_LIST(x) STRINGIZE(x)
#define RECENT_LIST_STR "/proc/net/xt_recent/"STRINGIZE_RECENT_LIST(RECENT_LIST)

/*
 * Get the IP of the ssh client from the SSH_CONNECTION
 * environment variable. If not set (ie. we're not in an
 * SSH session) return NULL. Otherwise return the IP 
 * prepended with a minus sign so it's useful for writing
 * to /proc/net/xt_recent/<listname> in order to remove
 * the IP from the blacklist.
 */
static char *getip()
{
	int i;
	char *ssh_con;
	static char ip[17];
	ssh_con = getenv("SSH_CONNECTION");
	if (!ssh_con)
		return NULL;
	ip[0] = '-';
	for (i = 1; i < 16; i++)
	{
		if (*ssh_con == 0x20)
		{
			ip[i] = 0;
			return ip;
		}
		ip[i] = *ssh_con++;			
	}
	ip[16] = 0;
	return ip;
}

int main(void)
{
	int r;
	const char *ip, *cmd;
	struct stat ssh_bad;
	ip = getip();
	cmd = getenv("SSH_ORIGINAL_COMMAND");

	if (!ip)
	{
		printf("This program cannot be executed directly.\n");
		printf("Please add \"ForceCommand /usr/bin/ssh-cmdexec\" to /etc/sshd_config.\n");
		printf("This build will remove the client IP from: " RECENT_LIST_STR "\n");
		return 0;
	}

	/*
	 * Remove our ip from the recent list
	 */
	if (!stat(RECENT_LIST_STR, &ssh_bad))
	{
		int fd;
		if ((fd = open(RECENT_LIST_STR, O_WRONLY)) != -1)
		{
			r = write(fd, ip, strlen(ip) + 1);
			close(fd);
		}
	}

	/*
	 * Drop setuid privileges
	 */
	r = setuid(getuid());

	/*
	 * if the user is executing a command via ssh then execute the
	 * command, otherwise execute the shell
	 */
	if (cmd && strlen(cmd))
	{
		r = system(cmd);
	}
	else
	{
		const char *shell = getenv("SHELL");
		if (!shell)
			shell = DEFAULT_SHELL;
		execv(shell, (char * const[]) { strdup(shell), NULL });
	}

	return (r = 0);
}

