#!/bin/bash

source scripts/helpers.sh

# written by sappho.io

# TODO: use tmpfs
tmp="/home/gitlab-runner/spaceship-gh"

gl_origin="git@gitlab.com:sapphonie/Spaceship-Servers.git"
gh_origin="git@github.com:sapp"

bootstrap ()
{
    if [ ! -d "${tmp}/gs" ]; then
        info "-> Cloning repo!"
        git clone ${gl_origin} \
        -b master --single-branch ${tmp}/gs \
        --depth 50 --progress
        cd ${tmp}/gs || exit 255
        info "-> moving master to gl_master"
        git checkout -b gl_master
        git branch -D master
    else
        cd ${tmp}/gs || exit 255
    fi

    if ! git remote | grep gl_origin > /dev/null; then
        info "-> adding gitlab remote"
        git remote add gl_origin ${gl_origin}
    fi

    if ! git remote | grep gh_origin > /dev/null; then
        info "-> adding github remote"
        git remote add gh_origin ${gh_origin}
    fi

    info "-> detatching"
    git switch --detach HEAD

    info "-> deleting stripped-master"
    git branch -D stripped-master

    important "-> fetching gh"

    info "-> fetching gh origin"
    git pull -X theirs gh_origin master:gh_master --no-ff -f --no-edit --progress

    important "-> fetching gl"

    info "-> fetching gl origin"
    git pull -X theirs gl_origin master:gl_master --no-ff -f --no-edit --progress


    git checkout gh-master
    git checkout -b stripped-master
    git merge -X theirs gl_master --no-edit --squash --no-ff


    ok "bootstrapped!"
}

# used to use BFG for this
# but I didn't like the java dep and also
# git filter-repo is faster and updated more often
# -sapph
# https://github.com/newren/git-filter-repo

gfr="git filter-repo --force --preserve-commit-hashes"

bigblobs="--strip-blobs-bigger-than 100M"
sensfiles="--invert-paths --paths-from-file paths.txt --use-base-name"
senstext="--replace-text regex.txt"


stripchunkyblobs ()
{
    info "-> [gfr] stripping big blobs"

    ${gfr} ${bigblobs}

    ok "-> [gfr] stripped big blobs"
}


# we don't want to scan binaries or map files
movebinaries_out ()
{
    info "-> moving binaries out of repo to prevent scanning"

    rsync -zarv \
        --include="*/" \
        --include="*.bsp" \
        --include="*.smx" \
        --include="*.dll" \
        --include="*.so" \
        --exclude="*" \
        --remove-source-files \
        "${tmp}/gs/" "${tmp}/gs_bins/"

    ok "-> done moving binaries"

}

movebinaries_in ()
{
    info "-> moving binaries back into repo"

    rsync -zarv \
        --include="*/" \
        --include="*.bsp" \
        --include="*.smx" \
        --include="*.dll" \
        --include="*.so" \
        --exclude="*" \
        --remove-source-files \
        "${tmp}/gs_bins/" "${tmp}/gs/"

    ok "-> done moving binaries"
}

stripfiles ()
{
    info "-> [gfr] stripping sensitive files"

    true > paths.txt
    # echo our regex && literal paths to it
    {
        echo 'regex:private.*';
        echo 'regex:databases.*';
        echo 'discord.cfg';
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
    info "-> [gfr] stripping sensitive strings"

    true > regex.txt
    # echo our regex to it
    # i want to simplify this
    {
// ***REPLACED SRC PASSWORD***
        echo 'regex:(?m)(Basic .*==)==>***REPLACED API INFO***';
***REPLACED API KEY***
    } >> regex.txt

    ${gfr} ${senstext}
    rm regex.txt

    ok "-> [gfr] stripped sensitive strings"
}

push ()
{
    # donezo
    ok "-> pushing to gh"
    git push gh_origin stripped-master:master --force --progress
}

bootstrap
stripchunkyblobs
movebinaries_out
stripfiles
stripsecrets
movebinaries_in
sync
push
