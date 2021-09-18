#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/CreatorsTF/gameservers/stable/scripts/helpers.sh)

#
export TERM="screen"

# written by sappho.io

# TODO: use tmpfs
tmp="/home/steph/"

gh_branch="master"
#CI_DEFAULT_BRANCH="stable"

debug "setting git config..."

#
git config --global user.email "sappho@sappho.io"
git config --global user.name "Spaceship Servers Prod"
# for pushing lfs properly because we scrub files from history
git config --global lfs.allowincompletepush true
gl_origin="git@gitlab.com:sapphonie/Spaceship-Servers.git"
gh_origin="git@github.com:sapphonie/Spaceship-Servers.git"

bootstrap_raw ()
{
    if [ ! -d "${tmp}/gs_raw" ]; then
        info "-> Cloning repo!"
        git clone ${gl_origin} \
        -b ${CI_DEFAULT_BRANCH} --single-branch ${tmp}/gs_raw \
        --progress

        cd ${tmp}/gs_raw || exit 255

        info "-> moving ${CI_DEFAULT_BRANCH} to gl_master"
        git checkout -B gl_master
        git branch -D ${CI_DEFAULT_BRANCH}
    else
        cd ${tmp}/gs_raw || exit 255
    fi

    if ! git remote | grep gl_origin > /dev/null; then
        info "-> adding gitlab remote"
        git remote add gl_origin ${gl_origin}
    fi

    if ! git remote | grep gh_origin > /dev/null; then
        info "-> adding github remote"
        git remote add gh_origin ${gh_origin}
    fi



    info "-> detaching"
    git checkout --detach HEAD -f


    important "-> fetching gl"

    info "-> fetching gl origin just in case we need to recreate the branch"
    git fetch gl_origin --progress ${CI_DEFAULT_BRANCH}

    info "-> checking out gl origin master"
    git checkout -B gl_master gl_origin/${CI_DEFAULT_BRANCH}

    info "-> resetting to gl origin master"
    git reset --hard gl_origin/${CI_DEFAULT_BRANCH}

    info "-> fetching gl origin"
    git fetch gl_origin --progress ${CI_DEFAULT_BRANCH}

    info "-> merging into current branch"
    git merge -v FETCH_HEAD



    info "-> detaching"
    git checkout --detach HEAD -f



    important "-> fetching gh"

    info "-> fetching gh origin just in case we need to recreate the branch"
    git fetch gh_origin --progress ${gh_branch}

    info "-> checking out gh origin ${gh_branch}"
    git checkout -B gh_master gh_origin/${gh_branch} ||

    info "-> resetting to gl origin ${gh_branch}"
    git reset --hard gh_origin/${gh_branch}

    info "-> fetching gl origin again"
    git fetch gh_origin --progress ${gh_branch}

    info "-> merging into current branch"
    git merge -v FETCH_HEAD

    info "checking out into master"
    git checkout -B gl_master gl_origin/${CI_DEFAULT_BRANCH}
}

bootstrap_stripped ()
{
    info "rm-ing unclean repo"
    rm -rf ${tmp}/gs_stripped

    info "cloning"
    git clone ${tmp}/gs_raw ${tmp}/gs_stripped --progress

    info "cd-ing"
    cd ${tmp}/gs_stripped
    info "done"


    if ! git remote | grep gl_origin > /dev/null; then
        info "-> adding gitlab remote"
        git remote add gl_origin ${gl_origin}
    fi

    if ! git remote | grep gh_origin > /dev/null; then
        info "-> adding github remote"
        git remote add gh_origin ${gh_origin}
    fi


    info "-> moving master to stripped-master"
    git checkout -f gl_master
    git checkout -B stripped-master

#    info "-> lfs migrating"
#    git lfs migrate export --include="*" --everything
}

# used to use BFG for this
# but I didn't like the java dep and also
# git filter-repo is faster and updated more often
# -sapph
# https://github.com/newren/git-filter-repo
# ignore everything but stripped master when we can
gfr="git filter-repo --force --preserve-commit-hashes --refs stripped-master"


bigblobs="--strip-blobs-bigger-than 100M"
sensfiles="--invert-paths --paths-from-file paths.txt --use-base-name"


stripchunkyblobs ()
{
    info "-> [gfr] stripping big blobs"

    ${gfr} ${bigblobs}

    ok "-> [gfr] stripped big blobs"
}


stripfiles ()
{
    info "-> [gfr] stripping sensitive files"

    # clobber
    true > paths.txt
    # echo our regex && literal paths to it
    {
        echo 'regex:private.*';
        echo 'regex:databases.*';
        echo 'regex:economy.*';
        echo 'discord.cfg';
        echo 'discord_seed.sp';
        echo 'regex:server-staging.*';
    } >> paths.txt

    # invert-paths deletes these files
    ${gfr} ${sensfiles}
    rm paths.txt

    ok "-> [gfr] stripped sensitive files"
}

stripsecrets ()
{
    # strip sensitive strings
    #


    info "-> [bfg-ish] stripping sensitive strings"


    true > regex.txt
    # echo our regex to it
    # i want to simplify this
    {
// ***REPLACED SRC PASSWORD***
        echo 'regex:(?m)\***REPLACED API INFO***==>***REPLACED API INFO***';
***REPLACED API KEY***
    } >> regex.txt

    # quite dumb that i need to do this lol, this ignores our bins
    # and other useless junk we don't need to scan
    # also i have to manually hack bfg-ish to preserve commit hashes lol
    ./scripts/bfg-ish.py ./                                     \
    --replace-text regex.txt                                    \
    -fe="*.{smx,so,dll,bz2,jar,vtf,vmt,png,jpg,mdl,vtx,nav}"    \
    -fe="tf/maps"                                               \
    -fe="tf/materials"                                          \
    -fe="tf/models"                                             \
    -fe="tf/scripts"                                            \
    -fe="tf/sound"                                              \
    -fe="tf/addons/sourcemod/bins"                              \
    -fe="tf/addons/sourcemod/data"                              \
    -fe="tf/addons/sourcemod/gamedata"                          \
    -fe="tf/addons/sourcemod/plugins"                           \
    -fe="tf/addons/sourcemod/translations"
    # ./this essentially includes only:
    # ./tf/addons/sourcemod/scripting
    # ./tf/cfg/
    # ./scripts/
    # ./*
    #
    # but i cant figure out how bfgish's include/exclude works because
    # i tried -fi and it did not work as expected
    rm regex.txt

    ok "-> [bfg-ish] stripped sensitive strings"
}

syncdisk ()
{
    important "syncing";
    sync
    ok "done syncing"
}

push ()
{
    # donezo
    ok "-> pushing to gh"
    git push gh_origin stripped-master:${gh_branch} --progress --force
}

bootstrap_raw       || exit 255
bootstrap_stripped  || exit 255
stripchunkyblobs    || exit 255
stripfiles          || exit 255
stripsecrets        || exit 255
syncdisk            || exit 255
push                || exit 1
