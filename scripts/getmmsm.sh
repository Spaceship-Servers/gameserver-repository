#!/bin/bash

mm_url="https://mms.alliedmods.net/mmsdrop/1.12/mmsource-1.12.0-git1157-linux.tar.gz"
sm_url="https://www.sourcemod.net/smdrop/1.11/sourcemod-1.11.0-git6393-linux.tar.gz"

mm_dest="mm-1.12.1157.tgz"
sm_dest="sm-1.11.6893.tgz"

export destfolder="mmsm_xtracted"


echo "rming tempfolder"
rm -rfv /tmp/${destfolder}
echo "mkdiring new destfolder"
mkdir /tmp/${destfolder}
echo "cding to destfolder"
cd /tmp/$destfolder

echo "Curling Metamod Source"
curl "$mm_url" --output "$mm_dest" --limit-rate 4M


echo "Curling SourceMod"
curl "$sm_url" --output "$sm_dest" --limit-rate 4M

echo "Untarring Metamod Source"
tar xfv "$mm_dest" # -C "$destfolder"
echo "Untarring Metamod Source"
tar xfv "$sm_dest" # -C "$destfolder"

echo "rming tgz"
rm ./*.tgz -fv


echo "rming junk"
rm ./cfg                                    -rfv
rm ./addons/sourcemod/plugins               -rfv
rm ./addons/sourcemod/scripting             -rfv
rm ./addons/sourcemod/configs               -rfv
# this gets linux64 folder too lmao
find . -name "*x64*"            -exec rm {} -rfv    \;
find . -name "*blade.so"        -exec rm {} -fv     \;
find . -name "*bms.so"          -exec rm {} -fv     \;
find . -name "*css.so"          -exec rm {} -fv     \;
find . -name "*csgo.so"         -exec rm {} -fv     \;
find . -name "*dods.so"         -exec rm {} -fv     \;
find . -name "*doi.so"          -exec rm {} -fv     \;
find . -name "*ep1.so"          -exec rm {} -fv     \;
find . -name "*ep2.so"          -exec rm {} -fv     \;
find . -name "*hl2dm.so"        -exec rm {} -fv     \;
find . -name "*insurgency.so"   -exec rm {} -fv     \;
find . -name "*l4d*.so"         -exec rm {} -fv     \;
find . -name "*nd.so"           -exec rm {} -fv     \;
find . -name "*sdk2013.so"      -exec rm {} -fv     \;

echo "DONE"
