# Arch Linux

## Installation (BRTFS on Luks)

### Init

1. Démarrer sur la clef USB

2. Activer le clavier en français :

```
loadkeys fr-latin1
```

3. Se connecter à internet via le wifi :
```
iwctl
device list
```
Ça doit afficher une liste de tes carte wifi. Il est probable que tu n'en es qu'une : wlan0
On va ensuite se afficher les réseaux disponibles :
```
//remplacer `wlan0` par le nom de ton device au besoin
station wlan0 scan
station wlan0 get-networks
```
relève le SSID du réseau auquel tu veux te connecter et connecte toi :
```
station wlan0 connect **MON_SSID**
exit
```

4. Vérifier si on a une ip avec `ip a`, sinon activer dchpd :

```
dhcpcd
```
5. vérifier qu'on est connecté :
 ```
 ping google.com
 ```


### Partitionnement

> Si t'es sur un laptop avec un disque NVMe, les partitions seront surement nommées `/dev/nvme0nX` plutôt que `/dev/sdaX`

1. Ouvrir gdisk et créer la table de partition

```
gdisk /dev/sda
o (Create a new empty GUID partition table (GPT))
Proceed? Y
```

2. Créer la partition EFI /boot
> En cas de dual boot windows cette partition a déjà été crée par l'installation windows. Passer à l'étape 3

```
n (Add a new partition)
Partition number 1
First sector 2048 (default)
Last sector +512M
Hex code EF00
```

3. Créer la partition principale

```
n (Add a new partition)
Partition number 2
First sector 2099200 (default)
Last sector (press Enter to use remaining disk)
Hex code 8300
```

4. Vérifier que tout est ok en entrant `p`. Ça devrait ressembler à ça :

```
Number Start (sector) End (sector) Size Code Name
1 2048 1050623 512.0 MiB EF00 EFI System
2 1050624 500118158 238.0 GiB 8300 Linux filesystem
```

5. Enregistrer et quitter

```
w
Y
```

6 Créer l'encryption container

```
cryptsetup luksFormat /dev/sda2
Are you sure? YES
Enter passphrase (twice)
```

7. Ouvrir le container créé

```
cryptsetup --allow-discards --persistent open /dev/sda2 btrfs-system
```

8. Formatter les partitions

```
mkfs.vfat -F32 /dev/sda1
mkfs.btrfs -L btrfs /dev/mapper/btrfs-system
```

9. Créer les subvolumes BTRFS

```
mount /dev/mapper/btrfs-system /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/swap
umount /mnt
mount -o subvol=root,ssd,compress=lzo,discard /dev/mapper/btrfs-system /mnt
mkdir /mnt/{boot,home,swap}
mount -o subvol=home,ssd,compress=lzo,discard /dev/mapper/btrfs-system /mnt/home
mount -o subvol=swap,ssd,discard /dev/mapper/btrfs-system /mnt/swap
```

10. (optionnel) Créer le fichier de SWAP

```
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile
dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count=8192 status=progress
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile
```

11. Enfin, on monte le volume `/boot`

```
mount /dev/sda1 /mnt/boot
```

### Installation du système

1. Installation des packages minimaux

```
pacstrap /mnt base base-devel btrfs-progs vim efibootmgr sudo zsh zsh-completions grml-zsh-config intel-ucode linux linux-firmware dhcpcd networkmanager
```
NB: remplacer `intel-ucode` par `amd-ucode` en cas de processeur amd

2. Générer le fstab

```
genfstab -U /mnt > /mnt/etc/fstab
```
Ça devrait ressembler à ça :

```
UUID=5f55843f-d4ef-4c9c-bb43-d6ceb0d99c4d / btrfs rw,relatime,ssd,compress=lzo,space_cache,subvol=root,discard 0 0
UUID=5f55843f-d4ef-4c9c-bb43-d6ceb0d99c4d /home btrfs rw,relatime,ssd,compress=lzo,space_cache,subvol=home,discard 0 0
UUID=5f55843f-d4ef-4c9c-bb43-d6ceb0d99c4d /swap btrfs rw,relatime,ssd,space_cache,subvol=swap,discard 0 0
/swap/swapfile none swap defaults 0 0
UUID=AB0E-6CD2 /boot vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2
```

3. Configurer la langue, l'heure et le hostname :

```
arch-chroot /mnt /bin/zsh
chsh -s /bin/zsh
```

4. Configurer le hostname

```
echo computer_name > /etc/hostname
```

5. Configurer la langue et les locales :

```
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
vim /etc/locale.gen (uncomment en_GB.UTF-8 and fr_FR.UTF-8)
locale-gen
echo LANG=en_GB.UTF-8 > /etc/locale.conf
echo KEYMAP=fr-latin1 > /etc/vconsole.conf
passwd
```

6. Ajouter la configuration suivante à `/etc/mkinitcpio.conf`

```
MODULES=(crc32c-intel)
HOOKS=(base systemd udev autodetect modconf block sd-encrypt btrfs resume filesystems keyboard fsck)
```

7. Générer les fichiers du kernel :

```
mkinitcpio -p linux
```

8. Générer la conf de boot

```
bootctl --path=/boot install
```

9. Copier l'uuid de la partition btrfs directement dans le fichier de conf pour pas se faire chier à le taper à la main :

```
lsblk -o name,uuid | grep btrfs | awk '{print $2}' > /boot/loader/entries/arch.conf
```
> Attention, si tu as un disque sdX et non nvme, utilise plutôt la commande suivante:
{.is-warning}


```
lsblk -o name,uuid | grep sda2 | awk '{print $2}' > /boot/loader/entries/arch.conf
```

> Attention (bis) : il est possible que lsblk n'arrive pas à trouver les uuid. Tu peut utiliser blkid à la place en mettant le nom de ta partition à la place de nvme0n1p5:


```
blkid | grep nvme0n1p5 | awk '{print $2}' > /boot/loader/entries/arch.conf
```


10. Modifier le fichier `/boot/loader/entries/arch.conf` en gardant l'uuid pour qu'il ressemble à la conf suivante

```
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options rd.luks.name=**UUID ICI**=btrfs-system luks.options=discard root=/dev/mapper/btrfs-system rw rootflags=subvol=root quiet
```

> Pour un processeur intel, il est possible de rajouter la ligne suivante:
{.is-info}

```
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img ## Cette ligne
initrd /initramfs-linux.img
options rd.luks.name=**UUID ICI**=btrfs-system luks.options=discard root=/dev/mapper/btrfs-system rw rootflags=subvol=root quiet
```

> Pour un processeur amd:
{.is-info}

```
title Arch Linux
linux /vmlinuz-linux
initrd /amd-ucode.img ## Cette ligne
initrd /initramfs-linux.img
options rd.luks.name=**UUID ICI**=btrfs-system luks.options=discard root=/dev/mapper/btrfs-system rw rootflags=subvol=root quiet
```

11. Editer le fichier `/boot/loader/loader.conf`

```
timeout 3
default arch.conf
```


12. Set un password pour l'utilisateur root

```
passwd
```

13. C'est le moment de reboot pour voir si ça marche ou si il faut tout recommencer !

```
exit
umount -R /mnt
reboot
```

## Post Install


1. Créer l'utilisateur

```
useradd -m -g users -G wheel username
passwd username
```

2. Activer sudo pour l'utilisateur

Lancer visudo : `EDITOR=vim visudo` et decommenter la ligne suivante :

```
%wheel ALL=(ALL:ALL) ALL
```

3. Configurer le réseau

Activer et lancer Network Manager :
```
sudo systemctl enable --now NetworkManager
```

4. Installer `yay` pour pouvoir installer des packages de l'AUR

```
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
```

#### Paquets potentiellement essentiels

- networkmanager
- xorg-server
- cocogitto

## Dual boot Windows 10/11



> Installer windows avant linux. Pour se simplifier la vie, utiliser ventoy qui te permet de mettre plusieurs iso sur une seule clef bootable
1. Installer une première fois windows. Reboot et aller jusqu'au bout de la procédure de première connexion

2. Désactiver le démarrage rapide dans Action qui suit la fermeture du capot

### Partitonnage
La partition EFI crée par windows est trop petite pour installer un dual boot(100Mo). Il faut donc la redimensionner, mais windows crée toutes ses partitions à la suite. On va donc devoir les supprimer et les recréer.
> Il est déconseillé de déplacer des partitions (notamment système). Si vous ne pouvez pas vous permettre de perdre vos données, vous pouver tout de même essayer de déplacer vos partitions windows pour libérer 400Mo d'espace devant votre partition EFI mais il est vivement recommandé de faire une sauvegarde de vos données auparavant

1. Utiliser une clef arch, gparted, etc... ou un outil directement depuis windows (Niubi free edition) pour supprimer toutes les partions autres que la partition EFI.
2. Étendre la partition EFI à 500Mo.
3. Rebooter sur la clef d'installation windows.
4. Créer une nouvelle partition dans l'espace libre. Lui donner la taille que vous voulez assigner à windows (50Go min).
   L'utilitaire crée automatiquement toutes les partitions nécessaires pour windows sans modifier la partion EFI.
5. Redémarrer, suivre la procédure d'installation au complet et mettre à jour windows pour être sûr d'avoir les derniers drivers

> Cette mise à jour peut prendre plusieurs dizaines de minutes voir plus d'une heure et impliquer plusieurs redémarrages.
{.is-warning}

6. Redémarrer sur la clef d'installation arch et suivre la procédure d'installation.

4. Utiliser une solution d'encryptage pour windows qui supporte le dual boot (VeraCrypt, BitDefender)
## Sway

1. Installer les composants basiques de sway :

```
pacman -S sway swayidle swaylock
```

2. Installer et activer gdm (qui détectera tout seul le sway.desktop)

```
pacman -S gdm
systemctl enable gdm
```
