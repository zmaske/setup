#!/bin/bash
drive="/dev/sda"
sfdisk $drive -f -X gpt << EOF
,+512M,ef,*
;
EOF
mkfs.fat -F32 $drive"1"
fatlabel $drive"1" BOOT
mkfs.btrfs -L -f ROOT $drive"2"
btrfs subvolume create /mnt/sda2
mount $drive"2" /mnt/sda2
mkdir /mnt/sda2/boot
mount $drive"1" /mnt/sda2/boot

basestrap /mnt/sda2 linux-zen linux-firmware base base-devel dinit elogind-dinit

fstabgen -U /mnt/sda2 >> /mnt/sda2/etc/fstab

artix-chroot /mnt/sda2 /bin/bash << EOF
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

pacman -Syyu
pacman -S --noconfirm --noprogressbar grub efibootmgr os-prober neofetch htop openssh git ufw
sed -i '/Color/s/^#//g' /etc/pacman.conf

sed -i "s/TIMEOUT=5/TIMEOUT=0/g" /etc/default/grub
sed -i "s/TIMEOUT_STYLE=menu/TIMEOUT_STYLE=hidden/g" /etc/default/grub
sed -i "s/="loglevel=3 quiet"/="loglevel=0 quiet splash"/g" /etc/default/grub
mkdir /boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
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
pacman -S --noconfirm dhcpcd connman-dinit connman-gtk wpa_supplicant bluez openvpn
ln -s ../connmand /etc/dinit.d/boot.d/
exit
EOF
umount -R /mnt
reboot