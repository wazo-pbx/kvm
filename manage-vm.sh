#!/bin/bash
VG='data'
BRIDGE='br0'
MEMORY=2048
DISK_SPACE=10000
MACADDR='52:54:00:11:22:35'
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
    $exec_cmd lvcreate -L ${vm_size}M -n $hostname $VG
}

delete_disk () {
    sleep 1
    $exec_cmd lvremove -f /dev/$VG/$hostname 
}

create_vm () {
    echo 'create vm'
    base_cmd="virt-install --connect qemu:///system --accelerate"
    host="--name $hostname --ram $mem_size --disk path=/dev/$VG/$hostname"
    network="--network bridge=$BRIDGE,mac=$MACADDR"
    other="--pxe --vnc  --os-variant=debiansqueeze"
    cmd="$base_cmd $host $network $other"
    $exec_cmd $cmd
}

destroy_vm () {
    $exec_cmd virsh destroy $hostname
    $exec_cmd virsh undefine $hostname
}
while getopts :a:h:m:s:dn opt
do
  case ${opt} in
    a) action=${OPTARG};;
    d) debug=1;;
    h) hostname=${OPTARG};;
    m) mem_size=${OPTARG};;
    n) dry_run=1;;
    s) vm_size=${OPTARG};;
    '?')  echo "${0} : option ${OPTARG} is not valid" >&2
          exit -1
    ;;
  esac
done

debug=${debug:-0}
dry_run=${dry_run:-0}

if [ $debug -eq 1 ]; then
    set -x
fi

vm_size=${vm_size:-$DISK_SPACE}
mem_size=${mem_size:-$MEMORY}

if [ -z $hostname ] || [ -z $action ]; then
    usage
fi

if [ $dry_run -eq 0 ]; then
    exec_cmd=''
else
    exec_cmd='echo'
fi

# TODO: check if virt-install is availlable
# TODO: test if br is availlable too
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
