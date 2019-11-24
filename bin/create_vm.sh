#!/bin/bash

VM_NAME=$1
VM_VCPUS=$2
VM_MEMSIZE=$3
VM_DISKSIZE=$4
VM_IP=$5
VM_GATEWAY=$6
VM_PASSWORD=$7
VNC_PASSWORD=$8

CLOUD_IMG=$9

AUTOKVM_PATH=/userap/glee/autokvm
AUTOKVM_TMP_PATH=${AUTOKVM_PATH}/tmp

VM_CONF_PATH=${AUTOKVM_PATH}/vm_conf/ubuntu
USERS_LIST_FILE=${VM_CONF_PATH}/users-list.txt

# get values from 'virsh capabilities | grep topology'
CPUCORES=2
CPUTHREADS=1

#KVM configuration
MAXVCPUS=2

HOST_NAME=`/bin/hostname`
NIC_NAME=`ip addr | grep "BROADCAST,MULTICAST,UP,LOWER_UP" | cut -d ":" -f 2 | xargs`
echo "Using NIC: [${NIC_NAME}]"
cpu_passthrough=TRUE

SSH_KEY_FILE=${VM_CONF_PATH}/${HOST_NAME}.pub
if [ ! -f ${SSH_KEY_FILE} ];then
    cp -rp ${HOME}/.ssh/id_rsa.pub ${SSH_KEY_FILE}
fi

VM_IMAGE_PATH=/var/lib/libvirt/images
VM_IMAGEFILE=${VM_IMAGE_PATH}/${VM_NAME}.qcow2

# pre-check
if [ ! -d ${AUTOKVM_TMP_PATH} ];then
    mkdir -p ${AUTOKVM_TMP_PATH}
fi

# pre-check
if [ -f ${VM_IMAGEFILE} ];then
	echo "Image file ${VM_IMAGEFILE} exist."
	exit 1
fi

# prepare base image
cp -rp ${AUTOKVM_PATH}/images/ubuntu/${CLOUD_IMG} ${AUTOKVM_TMP_PATH}/${VM_NAME}.img
sudo qemu-img resize -f qcow2 ${AUTOKVM_TMP_PATH}/${VM_NAME}.img ${VM_DISKSIZE}

# prepare cloud-init
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

# customize image
echo "sudo virt-customize -a ${AUTOKVM_TMP_PATH}/${VM_NAME}.img --root-password password:${VM_PASSWORD} --timezone Asia/Taipei --hostname ${HOST_NAME}-${VM_NAME} --copy-in ${AUTOKVM_TMP_PATH}/50-cloud-init.yaml:/etc/netplan --copy-in ${USERS_LIST_FILE}:/tmp --run ${VM_CONF_PATH}/init-vm-commands.sh --ssh-inject root:file:${SSH_KEY_FILE} --ssh-inject ado:file:${SSH_KEY_FILE} --ssh-inject glee:file:${SSH_KEY_FILE} --firstboot ${VM_CONF_PATH}/firstboot.sh"
sudo virt-customize -a ${AUTOKVM_TMP_PATH}/${VM_NAME}.img --root-password password:${VM_PASSWORD} --timezone Asia/Taipei --hostname ${HOST_NAME}-${VM_NAME} --copy-in ${AUTOKVM_TMP_PATH}/50-cloud-init.yaml:/etc/netplan --copy-in ${USERS_LIST_FILE}:/tmp --run ${VM_CONF_PATH}/init-vm-commands.sh --ssh-inject root:file:${SSH_KEY_FILE} --ssh-inject ado:file:${SSH_KEY_FILE} --ssh-inject glee:file:${SSH_KEY_FILE} --firstboot ${VM_CONF_PATH}/firstboot.sh

# deploy image
sudo qemu-img convert -f qcow2 -O qcow2 ${AUTOKVM_TMP_PATH}/${VM_NAME}.img ${VM_IMAGEFILE}

# define VM

if [[ "$cpu_passthrough" == TRUE ]] ; then
  echo "cpu_passthrough = '${cpu_passthrough}'"
  virt-install  --name ${VM_NAME} --memory ${VM_MEMSIZE} --disk /var/lib/libvirt/images/${VM_NAME}.qcow2 --import --os-type=linux --os-variant=ubuntu18.04  --cpu host-passthrough,cache.mode=passthrough --vcpus=${VM_VCPUS},maxvcpus=${MAXVCPUS},sockets=1,cores=${CPUCORES},threads=${CPUTHREADS} --graphics vnc,listen=0.0.0.0,port=-1,password=${VNC_PASSWORD} --video qxl --network type=direct,source=${NIC_NAME} --noautoconsole
else
  echo "cpu_passthrough = '${cpu_passthrough}'"
  virt-install  --name ${VM_NAME} --memory ${VM_MEMSIZE} --disk /var/lib/libvirt/images/${VM_NAME}.qcow2 --import --os-type=linux --os-variant=ubuntu18.04  --vcpus=${VM_VCPUS},maxvcpus=${MAXVCPUS},sockets=1,cores=${CPUCORES},threads=${CPUTHREADS} --graphics vnc,listen=0.0.0.0,port=-1,password=${VNC_PASSWORD} --video qxl --network type=direct,source=${NIC_NAME} --noautoconsole
fi
