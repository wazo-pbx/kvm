#!/bin/bash
VOLUME_GROUP='data'
BRIDGE='br0'
MEMORY=2048
DISK_SPACE=10000
MACADDR='52:54:00:11:22:35'
# TODO test shunit2 to test the code


usage () {
    cat << EOF
    usage : $(basename $0) -h hostame -a action [-m memory_size] [-s disk_size]
                [-b bridge] [-d] [-n] [-v vg]
        -a : availables actions are destroy or create (mandatory)
        -b : specify bridge 
        -d : debug mode
        -h : hostname (mandatory)
        -m : memory size in megabytes (default 1G)
        -n : dry run, print actions
        -s : vm disk space size in megabytes (default 10G)
        -v : volume group where to create logical volume
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
    echo "Creating logical volume"
    $exec_cmd lvcreate -L ${vm_size}M -n $hostname $volume_group
}

delete_disk () {
    echo "Deleting logical volume"
    sleep 1
    # workaround to avoid autopartionning error 
    $exec_cmd dd if=/dev/zero of=$volume bs=1M count=300 &> /dev/null
    sleep 1
    $exec_cmd lvremove -f $volume
}

create_vm () {
    base_cmd="virt-install --connect qemu:///system --accelerate"
    host="--name $hostname --ram $mem_size --disk path=$volume"
    network="--network bridge=$bridge,mac=$MACADDR"
    other="--pxe --vnc  --os-variant=debiansqueeze"
    cmd="$base_cmd $host $network $other"
    $exec_cmd $cmd
}

destroy_vm () {
    $exec_cmd virsh destroy $hostname
    $exec_cmd virsh undefine $hostname
}

check_virt () {
    # TODO: check if virt-install, libvirt, kvm
    return 0
}

check_network () {
    # TODO: test if bridge is configured
    return 0
} 

check_disk () {
    # TODO: test if volume group is available
    return 0
} 
check_env () {
    check_virt
    check_network
    check_disk
}


while getopts :a:b:h:m:s:v:dn opt
do
  case ${opt} in
    a) action=${OPTARG};;
    b) bridge=${OPTARG};;
    d) debug=1;;
    h) hostname=${OPTARG};;
    m) mem_size=${OPTARG};;
    n) dry_run=1;;
    s) vm_size=${OPTARG};;
    v) volume_group=${OPTARG};;
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
volume_group=${volume_group:-$VOLUME_GROUP}
bridge=${bridge:-$BRIDGE}
volume=/dev/$volume_group/$hostname

if [ -z $hostname ] || [ -z $action ]; then
    usage
fi

if [ $dry_run -eq 0 ]; then
    exec_cmd=''
else
    exec_cmd='echo'
fi

check_env

if [[ $action =~ create|destroy ]]; then
    if [ $action == 'create' ]; then
        if [ $(is_vm_exist) -eq 0 ]; then
            prepare_disk
            create_vm
        else
            echo 'a vm with this name already exist'
        fi
    else
        if [ $(is_vm_exist) -eq 1 ]; then
            destroy_vm
            delete_disk
        else
            echo 'this vm does not exist'
        fi
    fi
else
    usage
fi
