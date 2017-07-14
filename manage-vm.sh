#!/bin/bash
VOLUME_GROUP='data'
BRIDGE='br0'
MEM_SIZE=2048
DISK_SPACE=10000
# TODO test shunit2 to test the code


usage () {
    cat << EOF
    usage : $(basename $0) -h hostame -e action -a mac_addr [-m memory_size]
                [-s disk_size] [-b bridge] [-t lvm] [-d] [-n] [-v vg]
        -a : mac address
        -b : specify bridge 
        -c : cdrom path
        -d : debug mode
        -e : availables actions are delete or create (mandatory)
        -h : hostname (mandatory)
        -m : memory size in megabytes (default 1G)
        -n : dry run, print actions
        -t : disk type lvm or qcow2 (qcow2 default)
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

create_disk () {
    # virt-install will create qcow2 disk later
    if [ $disk_type = 'lvm' ]; then
        create_lvm
    fi
}

create_lvm () {
    echo "Creating logical volume"
    $exec_cmd lvcreate -L ${vm_size}M -n $hostname $volume_group
}

delete_disk () {
    if [ $disk_type = 'qcow2' ]; then
        delete_qcow
    else
        delete_lvm
    fi
}

delete_lvm () {
    echo "Deleting logical volume"
    sleep 1
    # workaround to avoid autopartionning error 
    $exec_cmd dd if=/dev/zero of=$volume bs=1M count=300 &> /dev/null
    sleep 1
    $exec_cmd lvremove -f $volume
}

delete_qcow () {
    $exec_cmd rm $qcow_file
}

configure_and_start () {
    disk_in_giga=$(perl -e "print $DISK_SPACE/1000")
    base_cmd="virt-install --connect qemu:///system --accelerate"
    host="--name $hostname --ram $mem_size"
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
    if [ $disk_type = 'qcow2' ]; then
        disk="--disk path=$qcow_file,format=qcow2"
    else
        disk="--disk path=$volume,size=$disk_in_giga"
    fi
    other="--vnc --os-variant=debianjessie"
    qemu-img create -f qcow2 $qcow_file ${disk_in_giga}G
    cmd="$base_cmd $host $network $boot $disk $other"
    $exec_cmd $cmd
}

shutdown_and_remove_vm () {
    $exec_cmd virsh destroy $hostname
    $exec_cmd virsh undefine $hostname
}

check_virt () {
    packages="virtinst libvirt-bin qemu-kvm"
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

create_vm () {
    if [ $(is_vm_exist) -eq 0 ]; then
        create_disk
        configure_and_start
    else
        echo 'a vm with this name already exist'
    fi
}

delete_vm () {
    if [ $(is_vm_exist) -eq 1 ]; then
        shutdown_and_remove_vm
        delete_disk
    else
        echo 'this vm does not exist'
    fi
}

while getopts :a:b:c:e:h:m:s:t:v:dn opt
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
    t) disk_type=${OPTARG};;
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
disk_type=${disk_type:-'qcow2'}
bridge=${bridge:-$BRIDGE}
volume=/dev/$volume_group/$hostname
qcow_file=/var/lib/libvirt/images/$hostname.qcow2

if [ -z $hostname ] || [ -z $execute ]; then
    usage
fi

if [ $dry_run -eq 0 ]; then
    exec_cmd=''
else
    exec_cmd='echo'
fi

check_env

case $execute in
    create)  create_vm;;
    delete)  delete_vm;;
    *) usage;;
esac
