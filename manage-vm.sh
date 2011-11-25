#!/bin/bash
VOLUME_GROUP='data'
BRIDGE='br0'
MEM_SIZE=2048
DISK_SPACE=10000
# TODO test shunit2 to test the code


usage () {
    cat << EOF
    usage : $(basename $0) -h hostame -e action -a mac_addr [-m memory_size]
                [-s disk_size] [-b bridge] [-d] [-n] [-v vg]
        -a : mac address
        -b : specify bridge 
        -c : cdrom path
        -d : debug mode
        -e : availables actions are destroy or create (mandatory)
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
    host="--name $hostname --ram $mem_size --disk path=$volume,size=1"
    if [ -z $mac_addr ]; then
        network="--network bridge=$bridge"
    else
        network="--network bridge=$bridge,mac=$mac_addr"
    fi
    if [ -z $cdrom ]; then
        boot="--pxe"
    else
        boot="--cdrom $cdrom"
    fi
    other="--vnc --os-variant=debiansqueeze"
    cmd="$base_cmd $host $network $boot $other"
    $exec_cmd $cmd
}

destroy_vm () {
    $exec_cmd virsh destroy $hostname
    $exec_cmd virsh undefine $hostname
}

check_if_running () {
    if [ $dry_run -eq 0 ]; then
        state=$(virsh dominfo $hostname | grep State | awk '{print $2}')
        while [ $state == 'running' ]; do
            state=$(virsh dominfo $hostname | grep State | awk '{print $2}')
        done
    fi
    return 0
}


start_vm () {
    $exec_cmd virsh start $hostname
}

check_virt () {
    packages="virtinst libvirt-bin kvm"
    for package in $packages; do
        dpkg --status $package &> /dev/null
        if [ $? -ne 0 ]; then
            echo "You have to install $package"
            echo "$packages are required"
            exit -1
        fi
    done
    return 0
}

check_cmd () {
    cmd=$1
    arg=$2
    full_cmd="$cmd $arg"
    $full_cmd &> /dev/null
    status=$?
    if [ $status -ne 0 ]; then
        echo "$arg doesn't exist"
        exit $status
    fi
    return $status
}
check_network () {
    check_cmd "ip address show" "$bridge"
} 

check_disk () {
    check_cmd "vgs --noheadings" "$volume_group"
} 

check_boot () {
    check_cmd "ls $cdrom"
}

check_env () {
    check_virt
    check_network
    check_boot
    check_disk
}


while getopts :a:b:c:e:h:m:s:v:dn opt
do
  case ${opt} in
    a) mac_addr=${OPTARG};;
    b) bridge=${OPTARG};;
    c) cdrom=${OPTARG};;
    d) debug=1;;
    e) execute=${OPTARG};;
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
mem_size=${mem_size:-$MEM_SIZE}
mac_addr=${mac_addr:-$MAC_ADDR}
volume_group=${volume_group:-$VOLUME_GROUP}
bridge=${bridge:-$BRIDGE}
volume=/dev/$volume_group/$hostname

if [ -z $hostname ] || [ -z $execute ]; then
    usage
fi

if [ $dry_run -eq 0 ]; then
    exec_cmd=''
else
    exec_cmd='echo'
fi

check_env

if [[ $execute =~ create|destroy ]]; then
    if [ $execute == 'create' ]; then
        if [ $(is_vm_exist) -eq 0 ]; then
            prepare_disk
            create_vm
            if [ ! -z $cdrom ];
                check_if_running
                start_vm
            fi
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
