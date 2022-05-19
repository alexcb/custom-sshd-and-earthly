#!/bin/sh
set -e

echo "starting self-hosted-sshd entrypoint.sh"

# setup authorization keys
test -n "$AUTHORIZED_KEY" || (echo "FATAL: missing AUTHORIZED_KEY"; exit 1)
echo "$AUTHORIZED_KEY" >> ~git/.ssh/authorized_keys

# create initial repo
test -n "$REPO" || (echo "FATAL: missing repo name to create"; exit 1)
REPO_PATH="/home/git/$REPO"
git init --bare $REPO_PATH
git -C $REPO_PATH symbolic-ref HEAD refs/heads/main
chown -R git:git /home/git/

# run sshd without detaching, and log to stderr rather than syslog
/usr/sbin/sshd -D -e -p 2222
