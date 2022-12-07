#!/bin/bash
# colors
source scripts/helpers.sh

# a2s shennanigans
export STEAM_GAMESERVER_RATE_LIMIT_200MS=25
export STEAM_GAMESERVER_PACKET_HANDLER_NO_IPC=1

steamcmd/steamcmd.sh +force_install_dir ${PWD} +login anonymous +app_update 232250 validate +exit

ok "./srcds_run $*"

./srcds_run $*
