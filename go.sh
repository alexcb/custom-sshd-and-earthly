#!/bin/bash
set -ex

# guess the host IP; 127.0.0.1 won't work as the earthly-buildkit container will resolve localhost to within
# the container rather than the host (where the self-hosted sshd binary is bound to, due to --network=host)
my_ip=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# remove previous sshd container instance (makes re-running this script easier)
docker rm -f my-self-hosted-git-sshd || true

earthly ./sshd+sshd

mkdir -p /tmp/custom-sshd-and-earthly
cd /tmp/custom-sshd-and-earthly

# generate a new private/public key pair
ssh-keygen -t ed25519 -f sshd_ed25519_key -q -N "" -C "example-user-key"

# start the sshd instance, and authorize access via the generated sshd_ed25519_key
docker run --name my-self-hosted-git-sshd -d --network=host -e AUTHORIZED_KEY="$(cat sshd_ed25519_key.pub)" -e REPO="user/repo.git" alexcb132/gitsshd:749d9bdd010f0462795cb4a0fc4c1f47f21c7203 /bin/sh -c '/entrypoint.sh'
sleep 2 # give sshd time to start up

# start ssh agent
eval $(ssh-agent)

# make sure ssh-agent is closed when script ends
function finish {
  kill -9 "$SSH_AGENT_PID"
}
trap finish EXIT

# load in newly generated private key
ssh-add sshd_ed25519_key

# test ssh works (without generating known hosts file)
ssh -p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "git@$my_ip" 2>&1 > ssh.output || true
cat ssh.output
grep "successfully authenticated" ssh.output >/dev/null || (echo "ssh test failed"; exit 1)

# configure git to ignore ssh keys
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

# create a new repo
mkdir repo
git init repo
echo aGVsbG8gd29ybGQ= > repo/data
git -C repo add data
git -C repo -c commit.gpgsign=false commit -m "initial test commit"
git -C repo branch -m master main
git -C repo remote add origin "ssh://git@$my_ip:2222/~/user/repo.git"
git -C repo push --set-upstream origin main

# next configure earthly to use this repo

cat > sample-earthly-config <<EOF
git:
    myserver:
        pattern: myserver/([^/]+)/([^/]+)
        substitute: ssh://git@$my_ip:2222/home/git/\$1/\$2.git
        auth: ssh
        strict_host_key_checking: false
EOF

earthly --verbose --debug --config sample-earthly-config myserver/user/repo+foo
#earthly --verbose --config sample-earthly-config "$SCRIPT_DIR/example-git-clone+test"
