#!/usr/bin/env bash


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Helper functions
source ${SCRIPT_DIR}/helpers.sh

# [[ ${CI} ]] || { error "This script is only to be executed in GitLab CI"; exit 1; }

# Variable initialisation

export WORK_DIR="/srv/daemon-data"

debug "working dir: ${WORK_DIR}"



info "Copying repo to /tmp/cicici"
rm /tmp/cicici -rfv
mkdir -p /tmp/cicici
cp ${CI_PROJECT_DIR}/* /tmp/cicici/ -rf



# go to our directory with (presumably) gameservers in it or die trying
cd "${WORK_DIR}" || { error "can't cd to workdir ${WORK_DIR}!!!"; hook "can't cd to workdir ${WORK_DIR}"; exit 1; }

# iterate thru directories in our work dir which we just cd'd to
for dir in ./*/ ; do
    # we didn't find a git folder
    if [ ! -d "${dir}/.git" ]; then
        warn "${dir} has no .git folder! skipping"
        hook "${dir} has no .git folder!"
        # maybe remove these in the future
        continue
    fi
    # we did find a git folder! print out our current folder
    important "Operating on: ${dir}"

    # go to our server dir or die trying
    cd "${dir}" || { error "can't cd to ${dir}"; continue; }

    # branches and remotes
    CI_COMMIT_HEAD=$(git rev-parse --abbrev-ref HEAD)
    CI_LOCAL_REMOTE=$(git remote get-url origin)
    CI_LOCAL_REMOTE="${CI_LOCAL_REMOTE##*@}"
    CI_LOCAL_REMOTE="${CI_LOCAL_REMOTE/://}"
    CI_LOCAL_REMOTE="${CI_LOCAL_REMOTE%.git*}"
    CI_REMOTE_REMOTE="${CI_SERVER_HOST}/${CI_PROJECT_PATH}"

    info "Comparing branches ${CI_COMMIT_HEAD} and ${CI_COMMIT_REF_NAME}."
    info "Comparing local ${CI_LOCAL_REMOTE} and remote ${CI_REMOTE_REMOTE}."

    if [[ "${CI_COMMIT_HEAD}" == "${CI_COMMIT_REF_NAME}" ]] && [[ "${CI_LOCAL_REMOTE}" == "${CI_REMOTE_REMOTE}" ]]; then
        debug "branches match"
        info "Pulling git repo"

        info "-> removing all .so files so we don't crash!"
        find ./tf/addons/ -name *.so -exec rm {} -v \;

        info "-copying server from cicici"
        rsync -avzc --delete        \
        --exclude="*.vpk"           \
        --exclude="*.inf"           \
        --exclude="bin/"            \
        --exclude="custom/"         \
        --exclude="download/"       \
        --exclude="downloadlists/"  \
        --exclude="materials/"      \
        --exclude="media/"          \
        --exclude="replay/"         \
        --exclude="resource/"       \
        --exclude="scripts/"        \
        --exclude="stvdemos/"       \
        --exclude="workshop/"       \
        /tmp/cicici/tf ./

        info "-> copying metamod and sourcemod to server"
        rsync -avzc /tmp/mmsm_xtracted/* ./tf/

        # DON'T QUOTE THIS
        # bash ${SCRIPT_DIR}/pull.sh
    else
        important "Branches do not match, doing nothing"
    fi
    cd ..
done
