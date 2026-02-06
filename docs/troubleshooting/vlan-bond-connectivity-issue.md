# VLAN on Bond Interface TX Drop Issue

## Summary

qBittorrent pod lost VPN connectivity through Multus (ipvlan on VLAN 70). Root cause: Linux bonding driver's VLAN TX
path intermittently drops frames due to `NETDEV_TX_BUSY` + `noqueue` qdisc interaction on kernel 6.12.57-talos.

**Solution**: Bypass the bond by creating a VLAN sub-interface (`vpn0`) directly on the physical NIC instead of on
`bond0`.

## Symptoms

- qBittorrent pod's secondary interface (`net1`, 192.168.70.40/24) could not reach the gateway (192.168.70.1)
- ARP resolution for the gateway failed: `192.168.70.1 dev net1 FAILED`
- The setup had been working fine for 8 days 12 hours with 1.02 TB transferred before it stopped
- UniFi logs showed: `Qbittorrent disconnected from Outgoing VPN on USW Pro Max 24 Port 24`

## Environment

- **Nodes**: 6x Talos Linux v1.11.5, kernel 6.12.57-talos
- **NIC**: Intel 2.5GbE (igc driver), single NIC per node
- **Bond**: `bond0` in active-backup mode with a single slave (enp2s0 or enp3s0 depending on node)
- **VLANs**: `bond0.70` (VPN/Outgoing VPN), `bond0.30` (IOT)
- **CNI**: Multus with ipvlan L2 mode, NetworkAttachmentDefinition `vpn` in `kube-system`
- **Gateway**: UDM Pro Max (192.168.70.1) with AirVPN WireGuard tunnel
- **Switch**: USW Pro Max 24

## Investigation

### 1. ARP failure on pod interface

From inside the qBittorrent pod, ARP for the gateway was stuck in `FAILED` state. No ARP replies were received because
frames were never transmitted.

### 2. TX drops on bond0.70

On node `fool`:

```
bond0.70: tx_packets=11  tx_dropped=0  tx_errors=0
# But ip -s link show bond0.70 revealed:
TX: bytes  packets  errors  dropped   carrier  collsns
   2618      11       0     222430       0        0
```

Over 222,000 TX drops on `bond0.70` with only 11 successful packets. Same pattern on node `bee` (1,788 drops).

The drops were NOT counted on `bond0` itself — they occurred in the 8021q VLAN layer's `vlan_dev_hard_start_xmit` →
`dev_queue_xmit(bond0)` path.

### 3. Physical NIC VLAN works perfectly

Creating a VLAN directly on the physical NIC worked every time:

```sh
ip link add link enp2s0 name enp2s0.70 type vlan id 70
ip addr add 192.168.70.99/24 dev enp2s0.70
ip link set enp2s0.70 up
ping -c5 192.168.70.1  # 5/5 success, 0 drops
```

This confirmed the bond interface was the problem, not the switch, VLAN config, or network.

### 4. ENOBUFS errors

With a static ARP entry to bypass ARP resolution:

```
ping: sendmsg: No buffer space available
```

This `ENOBUFS` error comes from `dev_queue_xmit` when the qdisc drops the packet. `bond0` uses `noqueue` by default,
which drops frames immediately when the slave returns `NETDEV_TX_BUSY`.

### 5. qdisc workaround was not reliable

Adding `fq_codel` qdisc and txqueuelen to `bond0.70` temporarily helped but was not reliable:

```sh
tc qdisc replace dev bond0.70 root fq_codel
ip link set bond0.70 txqueuelen 1000
```

The drops still occurred because the VLAN xmit internally calls `dev_queue_xmit` on the parent bond, where `noqueue`
drops frames. Adding `fq_codel` to `bond0` itself also didn't help.

## What was tried (and didn't work)

| Attempt                                                 | Result                                       |
|---------------------------------------------------------|----------------------------------------------|
| Changing tagged VLAN management on switch ports (UniFi) | No effect                                    |
| Bouncing `bond0.70` (ip link set down/up)               | Temporary fix, drops resume                  |
| Deleting and recreating `bond0.70`                      | Temporary fix, drops resume                  |
| Enabling `tx-vlan-offload` on physical NIC              | Appeared to help briefly, not the actual fix |
| Adding `fq_codel` qdisc on `bond0.70`                   | Worked initially, then stopped               |
| Adding `fq_codel` qdisc on `bond0`                      | Did not help                                 |

## Root cause

A bug or limitation in the Linux bonding driver's VLAN TX path on kernel 6.12.57-talos. When transmitting through a VLAN
sub-interface on a bond (`bond0.70`), the 8021q driver calls `dev_queue_xmit` on the bond device. Because `bond0` uses
the `noqueue` qdisc (default for virtual devices), any transient `NETDEV_TX_BUSY` from the slave NIC causes immediate
packet drops with no retry/buffering.

This is intermittent — it worked for 8+ days before the drops started, and bouncing the interface sometimes temporarily
restores functionality.

## Solution

### 1. Create `vpn0` interface directly on physical NIC (DaemonSet)

A DaemonSet `fix-vlan-offload` in `kube-system` creates `vpn0` (VLAN 70 on the physical NIC, bypassing bond0):

```sh
# Get the physical NIC name from the bond's slave list
NIC=$(cat /sys/class/net/bond0/bonding/slaves | awk '{print $1}')
# Create VLAN directly on physical NIC
ip link add link $NIC name vpn0 type vlan id 70
ip link set vpn0 mtu 1500 up
tc qdisc replace dev vpn0 root fq_codel
ip link set vpn0 txqueuelen 1000
```

A watcher container checks every 30s that `vpn0` exists and recreates it if missing.

> **TODO**: This DaemonSet currently only exists in-cluster. It needs to be committed to the GitOps repo.

### 2. Update Multus NetworkAttachmentDefinition

Changed the master interface in `kubernetes/apps/kube-system/multus/networks/vpn.yaml`:

```diff
- "master": "bond0.70",
+ "master": "vpn0",
```

### 3. Verification

After restarting qBittorrent:

- 10/10 pings to gateway 192.168.70.1
- Public IP confirmed as AirVPN exit IP (213.152.161.91)
- Zero TX drops on `vpn0`

## Long-term considerations

- The `fix-vlan-offload` DaemonSet should be added to the GitOps repo for persistence
- This workaround bypasses the bond for VLAN 70 traffic only; bond0 still handles untagged and VLAN 30 traffic
- If the same issue affects VLAN 30 (IOT), a similar approach can be used
- Monitor for kernel updates that fix the bonding driver's VLAN TX drop behavior
- Consider whether the single-slave active-backup bond is still necessary, or if the physical NIC could be used directly
