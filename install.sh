#! /bin/sh
# Configure and install MinkeBox on a Debian based system

BRIDGE=br0
INTERFACES=/etc/network/interfaces
DHCPCD=/etc/dhcpcd.conf
NETDEV=/etc/systemd/network
REBOOT=0

echo "*** Checking for MinkeBox"
if [ -f /usr/bin/minkebox ]; then
    echo "--- MinkeBox already installed"
    exit 0
fi

#
# Install dependencies
#
echo "*** Install dependencies"
apt update
apt install -y bridge-utils net-tools ifupdown ca-certificates curl gnupg

#
# Check for docker install
#
echo "*** Checking for Docker install"
if docker > /dev/null 2>&1 ; then
    echo "--- Docker already installed"
else
    echo "--- Installing Docker"
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg /etc/apt/sources.list.d/docker.list
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
fi

#
# Check for bridge network
#
echo "*** Checking for bridge network '${BRIDGE}'"
if ip link show ${BRIDGE} > /dev/null 2>&1 ; then
    echo "--- Bridge network exists"
else
    echo "--- No bridge network configured. Will attempt to create one."

    ETH=$(ip route show default | sed "s/^.*dev \([A-Za-z0-9]*\) .*$/\1/")

    echo "--- Checking network configuration in ${INTERFACES}."
    NETCOUNT=$(grep -c "iface .* inet " ${INTERFACES})
    if [ "${NETCOUNT}" = "2" ]; then
        echo "--- Creating bridge network in ${INTERFACES} with ${ETH}"

        # Extract current network configuration
        IP=$(ip addr show ${ETH} | grep "inet " | sed "s/^.*inet \([0-9./]*\) .*$/\1/")
        BRD=$(ip addr show ${ETH} | grep "inet " | sed "s/^.*brd \([0-9./]*\) .*$/\1/")
        GW=$(ip route show default | sed "s/^.*via \([0-9.]*\) .*$/\1/")
        DHCP=$(grep -c "iface ${ETH} inet dhcp" ${INTERFACES})

        # Generate new interfaces
        cat > ${INTERFACES} <<__EOF__
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug ${ETH}
iface ${ETH} inet static

# The bridge
auto ${BRIDGE}
__EOF__
        if [ "${DHCP}" = "0" ]; then
            cat >> ${INTERFACES} <<__EOF__
iface ${BRIDGE} inet static
    address ${IP}
    broadcast ${BRD}
    gateway ${GW}
    bridge_ports ${ETH}
__EOF__
        else
            cat >> ${INTERFACES} <<__EOF__
iface ${BRIDGE} inet dhcp
    bridge_ports ${ETH}
__EOF__
        fi

        REBOOT=1

    elif [ "${NETCOUNT}" != "0" ]; then
        echo ">>> Not clever enough to understand the network configuration on this machine."
        echo ">>> Please create a bridge network ${BRIDGE} by hand and re-run this script."
        exit 1
    else
        echo "--- Checking network configuration in ${DHCPCD}"
        if [ ! -f ${DHCPCD} ]; then
            echo ">>> Not clever enough to understand the network configuration on this machine."
            echo ">>> Please create a bridge network ${BRIDGE} by hand and re-run this script."
            exit 1
        else
            echo "--- Creating bridge network in ${NETDEV} with ${ETH}"

            cat > ${NETDEV}/bridge-${BRIDGE}.netdev <<__EOF__
[NetDev]
Name=${BRIDGE}
Kind=bridge
__EOF__
            cat > ${NETDEV}/${BRIDGE}-member-${ETH}.network <<__EOF__
[Match]
Name=${ETH}

[Network]
Bridge=${BRIDGE}
__EOF__

            systemctl enable systemd-networkd

            echo "--- Editing ${DHCPCD}"
            echo "denyinterfaces wlan0 ${ETH}" > /tmp/dhcpcd
            cat ${DHCPCD} >> /tmp/dhcpcd
            echo "interfaces ${BRIDGE}" >> /tmp/dhcpcd
            cat /tmp/dhcpcd > ${DHCPCD}
            rm /tmp/dhcpcd

            REBOOT=1
        fi
    fi
fi

#
# Install MinkeBox
#
echo "*** Installing MinkeBox package"
rm -f /usr/share/keyrings/minkebox-keyring.gpg /etc/apt/sources.list.d/minkebox.list
curl -fsSL https://raw.githubusercontent.com/minkebox/repo/master/KEY.gpg | gpg --dearmor -o /usr/share/keyrings/minkebox-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/minkebox-keyring.gpg] https://raw.githubusercontent.com/minkebox/repo/master/ dev/" > /etc/apt/sources.list.d/minkebox.list
apt update
apt install -y minkebox

echo "*** MinkeBox successfully installed and running"

if [ "${REBOOT}" = "1" ]; then
    echo "***"
    echo "*** The network has been reconfigured. Please REBOOT so these changes can take effect."
    echo "***"
fi

exit 0
