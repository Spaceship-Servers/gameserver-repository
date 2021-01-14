echo `realpath ./`
steamcmd/steamcmd.sh +login anonymous +force_install_dir `realpath ./` +app_update 232250 +exit
./srcds_run $*