#!/bin/bash
. ./data
# TODO test shunit2 to test the code


usage () {
    cat << EOF
    usage : $(basename $0) -h hostame -a action [-m memory_size] [-s disk_size]
        -a : availables actions are destroy or create
        -m : memory size in megabytes (default 1G)
        -s : vm disk space size in megabytes (default 10G)
EOF
    exit
}

all_vm () {
    vms=$(virsh --quiet list --all | awk '{print $2}')
    echo $vms
}

is_vm_exist () {
    exist=0
    vms=$(all_vm)
    for vm in $vms; do
        if [ $vm = $hostname ]; then
            exist=1
        fi
    done
    echo $exist
}

prepare_disk () {
    lvcreate -L $vm_size -n $hostname $VG
}

delete_disk () {
    lvremove -f /dev/$VG/$hostname > /dev/null 2>&1
}

create_vm () {
    echo 'create vm'
    base_cmd="virt-install --connect qemu:///system --accelerate"
    host="--name $hostname --ram $mem_size --disk path=/dev/$VG/$hostname"
    network="--network bridge=$BRIDGE"
    other="--pxe --vnc  --os-variant=debiansqueeze"
    cmd="$base_cmd $host $network $other"
    $cmd
}

destroy_vm () {
    virsh destroy $hostname
    virsh undefine $hostname
}
while getopts :a:h:m:s:d opt
do
  case ${opt} in
    a) action=${OPTARG};;
    d) debug=1;;
    h) hostname=${OPTARG};;
    m) mem_size=${OPTARG};;
    s) vm_size=${OPTARG};;
    '?')  echo "${0} : option ${OPTARG} is not valid" >&2
          exit -1
    ;;
  esac
done

debug=${debug:-0}

if [ $debug -eq 1 ]; then
    set -x
fi

vm_size=${vm_size:-$MEMORY}
mem_size=${mem_size:-$DISK_SPACE}

if [ -z $hostname ] || [ -z $action ]; then
    usage
fi

if [[ $action =~ create|destroy ]]; then
    if [ $action == 'create' ]; then
        if [ $(is_vm_exist) -eq 0 ]; then
            echo "create $hostname"
            prepare_disk
            create_vm
        else
            echo 'a vm with this name already exist'
        fi
    else
        if [ $(is_vm_exist) -eq 1 ]; then
            echo "destroy $hostname"
            destroy_vm
            delete_disk
        else
            echo 'this vm does not exist'
        fi
    fi
else
    usage
fi
