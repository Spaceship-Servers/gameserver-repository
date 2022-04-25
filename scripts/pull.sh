#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Helper functions
source ${SCRIPT_DIR}/helpers.sh

# Variable initialisation
gitshallow=false
gitgc=false
gitgc_aggressive=false

usage()
{
    echo "Usage, assuming you are running this as a ci script, which you should be"
    echo "  -s culls ('shallowifies') all repositories to only have the last 25 commits, implies -h"
    echo "  -a runs aggressive git housekeeping on all repositories (THIS WILL TAKE A VERY LONG TIME)"
    echo "  -h runs normal git housekeeping on all repositories (git gc always gets run with --auto, this will force it to run)"
    echo "  -v enables debug printing"
    exit 1
}


[[ ${CI} ]] || { error "This script is only to be executed in GitLab CI"; exit 1; }

while getopts ":sahv" flag; do
    case "${flag}" in
        s) gitshallow=true              ;;
        a) gitgc_aggressive=true        ;;
        h) gitgc=true                   ;;
        v) export ctf_show_debug=true   ;;
        ?) usage                        ;;
    esac
done





git config --global user.email "sappho@sappho.io"
git config --global user.name "Spaceship TF Prod"

info "Finding empty objects"
numemptyobjs=$(find .git/objects/ -type f -empty | wc -l)
if (( numemptyobjs > 0 )); then
    error "FOUND EMPTY GIT OBJECTS, RUNNING GIT FSCK ON THIS REPOSITORY!"
    hook "FOUND EMPTY GIT OBJECTS! RUNNING GIT FSCK!"
    find .git/objects/ -type f -empty -delete
    warn "fetching before git fscking"
    git fetch -p
    warn "fscking!!!"
    git fsck --full
    cd ..
    exit 0
else
    ok "no empty objects found, repo is safe and sound"
fi

debug "cleaning any old git locks..."
rm -fv .git/index.lock

if ${gitshallow}; then
    warn "shallowifying repo on user request"
    info "clearing stash..."
    git stash clear

    info "expiring reflog..."
    git reflog expire --expire=all --all

    info "deleting tags..."
    git tag -l | xargs git tag -d

    info "setting git gc to automatically run..."
    gitgc=true
fi

info "-> removing all .so files so we don't crash!"
find ./tf/addons/ -name *.so -exec rm {} -v \;

info "-> copying mm/sm to server!"
rsync -rvzc /tmp/mmsm_xtracted/* ./tf/

info "-> fetching origin"
git fetch origin

info "-> hard resetting"
git reset --hard origin/HEAD

info "updating submodules..."
git submodule update --init --recursive

info "cleaning cfg folder..."
git clean -d -f -x tf/cfg/

info "cleaning maps folder..."
git clean -d -f tf/maps/
# ignore the output if it already scrubbed it
debug "running str0 to scrub steamclient spam"
python3 ./scripts/str0.py ./bin/steamclient.so -c ./scripts/str0.ini | grep -v "Failed to locate string"

info "git pruning"
git prune

# don't run this often
info "garbage collecting"
if ${gitgc_aggressive}; then
    debug "running aggressive git gc!!!"
    git gc --aggressive --prune=all
elif ${gitgc}; then
    debug "running git gc on user request"
    git gc
else
    debug "auto running git gc"
    git gc --auto
fi

ok "git repo updated on this server (${PWD})"
