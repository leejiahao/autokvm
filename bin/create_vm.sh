#!/bin/bash

# P1
VM_OS_NAME=$1
shift
# P2
VM_NAME=$1
shift
# P3
VM_VCPUS=$1
shift
# P4
VM_MEMSIZE=$1
shift
# P5
VM_DISKSIZE=$1
shift
# P6
VM_IP=$1
shift
# P7
VM_GATEWAY=$1
shift
# P8
VM_PASSWORD=$1
shift
# P9
VNC_PASSWORD=$1
shift
# P10
CLOUD_IMG=$1

AUTOKVM_PATH=/userap/glee/autokvm
AUTOKVM_TMP_PATH=${AUTOKVM_PATH}/tmp/${VM_OS_NAME}/${VM_NAME}

VM_CONF_PATH=${AUTOKVM_PATH}/vm_conf/${VM_OS_NAME}
USERS_LIST_FILE=${VM_CONF_PATH}/users-list.txt

VIRSH_CAPABILITIES_XML=`virsh capabilities`
SOCKETS=`echo $VIRSH_CAPABILITIES_XML | xmllint --xpath "string(//capabilities/host/cpu/topology/@sockets)" -`
CPUCORES=`echo $VIRSH_CAPABILITIES_XML | xmllint --xpath "string(//capabilities/host/cpu/topology/@cores)" -`
CPUTHREADS=`echo $VIRSH_CAPABILITIES_XML | xmllint --xpath "string(//capabilities/host/cpu/topology/@threads)" -`
MAXVCPUS=$(( $SOCKETS*$CPUCORES*$CPUTHREADS ))
echo "Sockets:${SOCKETS} Cores:${CPUCORES} Threads:${CPUTHREADS}: MaxVCPUS:${MAXVCPUS}"

HOST_NAME=`/bin/hostname`
NIC_NAME=` route | grep '^default' | grep -o '[^ ]*$' | head -n 1 `
echo "Using NIC: [${NIC_NAME}]"
cpu_passthrough=TRUE

SSH_KEY_FILE=${VM_CONF_PATH}/${HOST_NAME}.pub
if [ ! -f ${SSH_KEY_FILE} ];then
    echo "Copying SSH key [${SSH_KEY_FILE}]"
    cp -rp ${HOME}/.ssh/id_rsa.pub ${SSH_KEY_FILE}
fi

VM_IMAGE_PATH=/var/lib/libvirt/images
VM_IMAGE_TARGET_FILE=${VM_IMAGE_PATH}/${VM_NAME}.qcow2

# pre-check
if [ ! -d ${AUTOKVM_TMP_PATH} ];then
    mkdir -p ${AUTOKVM_TMP_PATH}
fi

# pre-check
if [ -f ${VM_IMAGE_TARGET_FILE} ];then
    echo "Image file ${VM_IMAGE_TARGET_FILE} exist."
    exit 1
fi

# prepare base image
echo "Staring prepare image ${AUTOKVM_TMP_PATH}/${VM_NAME}.img ..."
cp -rp ${AUTOKVM_PATH}/images/${VM_OS_NAME}/${CLOUD_IMG} ${AUTOKVM_TMP_PATH}/${VM_NAME}.img
sudo qemu-img resize -f qcow2 ${AUTOKVM_TMP_PATH}/${VM_NAME}.img ${VM_DISKSIZE}

# prepare cloud-init
case $VM_OS_NAME in
    ubuntu18.04 )
        echo "Preparing ${AUTOKVM_TMP_PATH}/50-cloud-init.yaml ..."
        cat > ${AUTOKVM_TMP_PATH}/50-cloud-init.yaml <<EOF
# This file is generated from information provided by
# the datasource.  Changes to it will not persist across an instance.
# To disable cloud-init's network configuration capabilities, write a file
# /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg with the following:
# network: {config: disabled}
network:
    ethernets:
        ens3:
            addresses:
            - ${VM_IP}/24
            gateway4: ${VM_GATEWAY}
            nameservers:
                addresses:
                - ${VM_GATEWAY}
                - 8.8.8.8
            dhcp4: no
    version: 2
EOF
    ;;
    centos7.0)
    echo "Preparing nmcli script ...";
        cat > ${AUTOKVM_TMP_PATH}/ifcfg-eth0 <<EOF
DEVICE=eth0
ONBOOT=yes
IPADDR=${VM_IP}
NETMASK=255.255.255.0
GATEWAY=${VM_GATEWAY}
EOF
    ;;
    *)
    echo "";
    ;;
esac

# customize image
case $VM_OS_NAME in
    ubuntu18.04 )
        echo "Running virt-customize ..."
        sudo virt-customize \
        -a ${AUTOKVM_TMP_PATH}/${VM_NAME}.img \
        --root-password password:${VM_PASSWORD} \
        --timezone Asia/Taipei \
        --hostname ${HOST_NAME}-${VM_NAME} \
        --copy-in ${AUTOKVM_TMP_PATH}/50-cloud-init.yaml:/etc/netplan \
        --copy-in ${USERS_LIST_FILE}:/tmp \
        --run ${VM_CONF_PATH}/init-vm-commands.sh \
        --ssh-inject root:file:${SSH_KEY_FILE} \
        --ssh-inject ado:file:${SSH_KEY_FILE} \
        --ssh-inject glee:file:${SSH_KEY_FILE} \
        --firstboot ${VM_CONF_PATH}/firstboot.sh
    ;;
    centos7.0 )
        echo "Running virt-customize ..."
        sudo virt-customize \
        -a ${AUTOKVM_TMP_PATH}/${VM_NAME}.img \
        --root-password password:${VM_PASSWORD} \
        --timezone Asia/Taipei \
        --hostname ${HOST_NAME}-${VM_NAME} \
        --copy-in ${AUTOKVM_TMP_PATH}/ifcfg-eth0:/etc/sysconfig/network-scripts \
        --copy-in ${USERS_LIST_FILE}:/tmp \
        --run ${VM_CONF_PATH}/init-vm-commands.sh \
        --ssh-inject root:file:${SSH_KEY_FILE} \
        --ssh-inject ado:file:${SSH_KEY_FILE} \
        --ssh-inject glee:file:${SSH_KEY_FILE} \
        --firstboot ${VM_CONF_PATH}/firstboot.sh \
        --selinux-relabel
    ;;
    *)
    echo "${VM_OS_NAME} is not supported by autokvm now."
    exit 1
    ;;
esac

# deploy image
sudo qemu-img convert -f qcow2 -O qcow2 ${AUTOKVM_TMP_PATH}/${VM_NAME}.img ${VM_IMAGE_TARGET_FILE}

# define VM

if [[ "$cpu_passthrough" == TRUE ]] ; then
  echo "cpu_passthrough = '${cpu_passthrough}'"
  virt-install  \
      --name ${VM_NAME} \
      --memory ${VM_MEMSIZE} \
      --disk ${VM_IMAGE_TARGET_FILE} \
      --import --os-type=linux \
      --os-variant=${VM_OS_NAME}  \
      --cpu host-passthrough,cache.mode=passthrough \
      --vcpus=${VM_VCPUS},maxvcpus=${MAXVCPUS},sockets=1,cores=${CPUCORES},threads=${CPUTHREADS} \
      --graphics vnc,listen=0.0.0.0,port=-1,password=${VNC_PASSWORD} \
      --video qxl \
      --network type=direct,source=${NIC_NAME} \
      --noautoconsole
else
  echo "cpu_passthrough = '${cpu_passthrough}'"
  virt-install  \
      --name ${VM_NAME} \
      --memory ${VM_MEMSIZE} \
      --disk ${VM_IMAGE_TARGET_FILE} \
      --import --os-type=linux \
      --os-variant=${VM_OS_NAME}  \
      --vcpus=${VM_VCPUS},maxvcpus=${MAXVCPUS},sockets=1,cores=${CPUCORES},threads=${CPUTHREADS} \
      --graphics vnc,listen=0.0.0.0,port=-1,password=${VNC_PASSWORD} \
      --video qxl \
      --network type=direct,source=${NIC_NAME} \
      --noautoconsole
fi
