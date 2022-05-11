#!/bin/bash
drive="/dev/"$(lsblk -S | awk {'print $1'} | sed -n '2 p')
sfdisk $drive -f -X gpt << EOF
,+512M,uefi,*
;
EOF
mkfs.fat -F32 $drive"1"
fatlabel $drive"1" BOOT
mkfs.btrfs -L ROOT $drive"2"
mount $drive"2" /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@var
btrfs su cr /mnt/@opt
btrfs su cr /mnt/@tmp
btrfs su cr /mnt/@.snapshots
umount /mnt
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@ $drive"2" /mnt
mkdir /mnt/{boot,home,var,opt,tmp,.snapshots}
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@home $drive"2" /mnt/home
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@opt $drive"2" /mnt/opt
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@tmp $drive"2" /mnt/tmp
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@.snapshots $drive"2" /mnt/.snapshots
mount -o subvol=@var $drive"2" /mnt/var
mkdir /mnt/boot
mount $drive"1" /mnt/boot

basestrap /mnt linux-zen linux-firmware base base-devel dinit elogind-dinit btrfs-progs

fstabgen -U /mnt >> /mnt/etc/fstab

artix-chroot /mnt /bin/bash << EOF
$hostname="osisa"
$username="user"
$password="setup"
$timezone="EST"
$language="en-US.UTF-8"

truncate -s 0 ./swapfile
chattr +C ./swapfile
btrfs property set ./swapfile compression none

ln -sf /usr/share/zoneinfo/posix/$timezone /etc/localtime
hwclock --systohc
sed -i "/"$language" "$language"/s/^#//g" /etc/locale.gen
locale-gen
echo "LANG="$language > /etc/locale.conf
echo $hostname > /etc/hostname

pacman -S --noconfirm --noprogressbar artix-archlinux-support
echo -e "
[extra]
Include = /etc/pacman.d/mirrorlist-arch
[community]
Include = /etc/pacman.d/mirrorlist-arch
" >> /etc/pacman.conf
pacman-key --populate archlinux

pacman -Syyu
pacman -S --noconfirm --noprogressbar grub grub-btrfs efibootmgr os-prober linux-headers dialog dialog dosfstools neofetch htop git xdg-utils xdg-user-dirs
sed -i '/Color/s/^#//g' /etc/pacman.conf
echo "MODULES=(btrfs)" >> /etc/mkinitcpio.conf
mkinitcpio -p linux-zen

sed -i "s/TIMEOUT=5/TIMEOUT=0/g" /etc/default/grub
sed -i "s/TIMEOUT_STYLE=menu/TIMEOUT_STYLE=hidden/g" /etc/default/grub
sed -i "s/="loglevel=3 quiet"/="loglevel=0 quiet splash"/g" /etc/default/grub
mkdir /boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Linux
#mount /dev/OTHER_OS
grub-mkconfig -o /boot/grub/grub.cfg

if grep -q "Intel" <<< $(cat /proc/cpuinfo | grep "vendor" ); then $cpu="intel"; fi
if grep -q "Amd" <<< $(cat /proc/cpuinfo | grep "vendor" ); then $cpu="amd"; fi
pacman -S --noconfirm $cpu"-ucode"

echo -e $password"\n"$password | passwd
useradd -m -g wheel $username
sed -i '/ %wheel ALL=(ALL) NO/s/^#//g' /etc/sudoers
sed -i "s/root:x:0:0:root:\/root:\/bin\/bash/root:x:0:0:root:\/root:\/sbin\/nologin/g" /etc/passwd
echo -e $password"\n"$password | passwd $username

echo "127.0.0.1\t\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t\"$hostname".local "$hostname > /etc/hosts
pacman -S --noconfirm dhcpcd connman-dinit connman-gtk wpa_supplicant bluez openvpn openssh ufw cups xdg
ln -s ../connmand /etc/dinit.d/boot.d/
exit
EOF
umount -l /mnt
echo "DONE"
