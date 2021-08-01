# written by sappho.io
whoami
bootstrap ()
{
    # bare --mirror gameserver repo ( uses a ssh key, don't even try it )
    # git clone git@gitlab.com:sapphonie/Spaceship-Servers.git -b master --single-branch /home/gitlab-runner/spaceship-bare --bare

    cd /home/gitlab-runner/spaceship-bare || exit 255

    echo "-> fetching master"
    git fetch origin master:master -f
}

# used to use BFG for this
# but I didn't like the java dep and also
# git filter-repo is faster and updated more often
# -sapph
# https://github.com/newren/git-filter-repo

stripchunkyblobs ()
{
    echo "-> stripping big blobs"
    git filter-repo --strip-blobs-bigger-than 100M --force
}

stripfiles ()
{
    echo "-> stripping sensitive files"
    # clobber any existing file
    true > paths.txt

    # echo our regex && literal paths to it
    {
        echo 'regex:private.*';
        echo 'regex:databases.*';
        echo 'discord.cfg';
    } >> paths.txt

    git filter-repo --invert-paths --paths-from-file paths.txt --force --use-base-name
}


stripsecrets ()
{
    # strip sensitive strings
    #
    echo "-> stripping sensitive strings"
    # clobber any existing file
    true > regex.txt

    # echo our regex to it
    {
        echo 'regex:(?m)^.*_password .*$==>// ***REPLACED SRC PASSWORD***';
***REPLACED PRIVATE URL******';
    } >> regex.txt

    git filter-repo --replace-text regex.txt --force
}

push ()
{
    if ! git remote | grep origin-gh > /dev/null; then
        echo "-> adding gh remote"
        git remote add origin-gh git@github.com:sapphonie/Spaceship-Servers.git
    fi

    # donezo
    echo "-> pushing to gh"
    git push origin-gh --force --progress --verbose --verbose --verbose
}

bootstrap
stripchunkyblobs
stripfiles
stripsecrets
push

