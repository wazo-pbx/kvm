#!/bin/bash

hostname="$1"
host -t a $hostname

if [ $? -eq 0 ]; then
    ssh $hostname 'grep postinst_script_launcher /etc/rc.local'
    while [ $? -ne 0 ]; do
        sleep 1;
        ssh $hostname 'grep postinst_script_launcher /etc/rc.local'
    done
fi
