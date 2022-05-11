#!/bin/bash
drive="/dev/"$(lsblk -S | awk {'print $1'} | sed -n '2 p')

#cryptsetup open --type plain -d /dev/urandom $drive to_be_wiped
#dd if=/dev/zero of=/dev/mapper/to_be_wiped bs=1M status=progress
#cryptsetup close to_be_wiped
#cryptsetup erase $drive
#cryptsetup luksDump $drive
#wipefs -a $drive

sfdisk $drive -f -X gpt << EOF
,+512M,uefi,*
;
EOF
mkfs.fat -F32 $drive"1" -f
fatlabel $drive"1" BOOT
mkfs.btrfs -L SYSTEM $drive"2" -f
mount $drive"2" /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@root
btrfs su cr /mnt/@srv
btrfs su cr /mnt/@log
btrfs su cr /mnt/@cache
btrfs su cr /mnt/@tmp
btrfs su li /mnt
umount /mnt
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@ $drive"2" /mnt
mkdir -p /mnt/{home,root,srv,var/log,var/cache,tmp}
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@home $drive"2" /mnt/home
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@root $drive"2" /mnt/root
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@srv $drive"2" /mnt/srv
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@log $drive"2" /mnt/var/log
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@cache $drive"2" /mnt/var/cache
mount -o defaults,noatime,compress=zstd,commit=120,subvol=@tmp $drive"2" /mnt/tmp
mkdir /mnt/boot/efi
mount $drive"1" /mnt/boot/efi

basestrap /mnt linux-zen linux-firmware base base-devel dinit elogind-dinit btrfs-progs snapper

fstabgen -U /mnt >> /mnt/etc/fstab

artix-chroot /mnt /bin/bash << EOF
hostname="osisa"
username="user"
password="setup"
timezone="EST"
language="en-US.UTF-8"

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

touch /var/swapfile
truncate -s 0 /var/swapfile
chattr +C /var/swapfile
btrfs property set /var/swapfile compression none
fallocate --length "$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')" /var/swapfile
chmod 600 /var/swapfile
mkswap /var/swapfile
swapon /var/swapfile
echo '/var/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
curl -sL https://github.com/osandov/osandov-linux/blob/master/scripts/btrfs_map_physical.c > btrfs_map_physical.c
gcc -O2 -o btrfs_map_physical btrfs_map_physical.c
./btrfs_map_physical /var/swapfile | sed -n "2p" | awk "{print \$NF}" > /tmp/swap_physical_offset
SWAP_PHYSICAL_OFFSET=$(cat /tmp/swap_physical_offset)
SWAP_OFFSET=$(echo "${SWAP_PHYSICAL_OFFSET} / $(getconf PAGESIZE)" | bc)
SWAP_UUID=$(findmnt -no UUID -T /var/swapfile)
RESUME_ARGS="resume=UUID=${SWAP_UUID} resume_offset=${SWAP_OFFSET}"
GRUB_DEFAULT=$(cat /etc/default/grub | grep CMDLINE_LINUX_DEFAULT)
GRUB_NEW=${GRUB_DEFAULT::-1}" "$RESUME_ARGS'"'
sed -i "s/"$GRUB_DEFAULT"/"$GRUB_NEW"/g" /etc/default/grub

sed -i "s/TIMEOUT=5/TIMEOUT=0/g" /etc/default/grub
sed -i "s/TIMEOUT_STYLE=menu/TIMEOUT_STYLE=hidden/g" /etc/default/grub
#sed -i "s/="loglevel=3 quiet"/="loglevel=0 quiet splash"/g" /etc/default/grub
mkdir /boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LINUX
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
pacman -S --noconfirm dhcpcd connman-dinit connman-gtk wpa_supplicant bluez openvpn openssh ufw cups
ln -s ../connmand /etc/dinit.d/boot.d/
#dinitctl enable {dhcpcd,connman-dinit,connman-gtk,wpa_supplicant,bluez,openvpn,openssh,ufw,cups}

exit
EOF
umount -l /mnt
echo "DONE"
