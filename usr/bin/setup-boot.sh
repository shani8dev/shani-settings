#!/bin/bash -e

# Define paths for the files
SHANI_BOOT_DIR="/usr/lib/shani-boot"
EFI_BOOT_DIR="/boot/efi/EFI/BOOT"
BOOT_ENTRY_DIR="/boot/efi/EFI/loader/entries"  # Fixed the path for systemd-boot entries
SHIM_BINARY="/usr/share/shim-signed/shimx64.efi"   # Path to the shim binary
MOK_MANAGER="/usr/share/shim-signed/mmx64.efi"     # Path to the MOK manager binary
MOK_DER="/usr/share/secureboot/keys/MOK.der"          # Path to the MOK DER certificate
SYSTEMD_BOOT="/usr/lib/systemd/boot/efi/systemd-bootx64.efi"  # Path to systemd-boot binary
FWUPD_EFI="/usr/lib/fwupd/efi/fwupdx64.efi"   # Path to fwupd EFI binary
KERNEL_IMAGE="vmlinuz"
INITRAMFS_IMAGE="initramfs.img"
INITRAMFS_FALLBACK_IMAGE="initramfs-fallback.img"

# Ensure necessary directories exist
mkdir -p "$EFI_BOOT_DIR"
mkdir -p "$BOOT_ENTRY_DIR"

# Helper function to install files with check for existence
install_file() {
    local source_file="$1"
    local destination_file="$2"
    
    if [[ ! -f "$source_file" ]]; then
        echo "❌ Error: $source_file not found."
        exit 1
    fi

    install -m0644 "$source_file" "$destination_file"
    echo "✅ Installed $source_file to $destination_file"
}

# Install shim, MOK manager, and MOK certificate to the boot directory
install_shim_and_mok() {
    echo "🔄 Installing shim, MOK manager, and MOK certificate..."
    
    install_file "$SHIM_BINARY" "$EFI_BOOT_DIR/BOOTX64.EFI"
    install_file "$MOK_MANAGER" "$EFI_BOOT_DIR/mmx64.efi"
    install_file "$MOK_DER" "$EFI_BOOT_DIR/MOK.der"
}

# Copy bootloader and kernel/initramfs images to EFI
copy_files_to_efi() {
    echo "🔄 Copying bootloader and kernel/initramfs files to EFI..."
    
    # Install systemd-boot and kernel/initramfs images
    install_file "$SYSTEMD_BOOT" "$EFI_BOOT_DIR/systemd-bootx64.efi"
    install_file "$SHANI_BOOT_DIR/$KERNEL_IMAGE" "$EFI_BOOT_DIR/$KERNEL_IMAGE"
    install_file "$SHANI_BOOT_DIR/$INITRAMFS_IMAGE" "$EFI_BOOT_DIR/$INITRAMFS_IMAGE"
    install_file "$SHANI_BOOT_DIR/$INITRAMFS_FALLBACK_IMAGE" "$EFI_BOOT_DIR/$INITRAMFS_FALLBACK_IMAGE"
}

# Install fwupd EFI binary for firmware updates
install_fwupd() {
    echo "🔄 Installing fwupd EFI binary..."
    install_file "$FWUPD_EFI" "$EFI_BOOT_DIR/fwupdx64.efi"
}

# Get root filesystem UUID and encryption type (if any)
get_root_info() {
    local root_device
    root_device=$(findmnt -n -o SOURCE /)
    local uuid encryption

    if [[ "$root_device" =~ /dev/mapper/ ]]; then
        # For encrypted LUKS devices
        if uuid=$(cryptsetup luksUUID "$root_device" 2>/dev/null); then
            encryption="luks"
        else
            uuid=$(blkid -s UUID -o value "$root_device")
            encryption="lvm"
        fi
    else
        uuid=$(blkid -s UUID -o value "$root_device")
        encryption="plain"
    fi
    echo "$uuid $encryption"
}

# Enroll MOK key if not already enrolled
enroll_mok() {
    if mokutil --test-key "$MOK_DER" &>/dev/null; then
        echo "✅ MOK key already enrolled."
    else
        echo "🔑 Enrolling MOK key..."
        if mokutil --import "$MOK_DER" --root-pw; then
            echo -e "\n⚠️ REBOOT REQUIRED! Complete enrollment via the UEFI boot menu."
        else
            echo "❌ Failed to enroll MOK key."
            exit 1
        fi
    fi
}

# Bypass MOK prompt on reboot (if already enrolled)
bypass_mok_prompt() {
    echo "Bypassing MOK prompt on reboot..."
    if [[ -f "$MOK_CRT" ]]; then
        local mok_der_temp="${MOK_CRT}.der"
        openssl x509 -in "$MOK_CRT" -outform DER -out "$mok_der_temp"
        if efivar -n MOKList -w -d "$mok_der_temp"; then
            echo "✅ MOK prompt bypassed."
        else
            echo "❌ Failed to bypass MOK prompt."
        fi
        rm -f "$mok_der_temp"
    else
        echo "⚠️ MOK certificate not found. Skipping MOK prompt bypass."
    fi

    # Disable Secure Boot validation if required
    echo "🚫 Disabling Secure Boot validation..."
    if mokutil --disable-validation; then
        echo -e "\n⚠️ REBOOT REQUIRED! Complete the process in MokManager on next boot."
    else
        echo "❌ Failed to disable Secure Boot validation." >&2
        exit 1
    fi
}

# Generate Unified Kernel Image (UKI) for Secure Boot
generate_cmdline() {
    local subvol="$1"
    read -r uuid encryption <<< "$(get_root_info)"
    
    local cmdline="quiet splash root=UUID=${uuid} ro rootflags=subvol=${subvol},ro"
    
    # Add options for encrypted disks if applicable
    if [[ "$encryption" == "luks" ]]; then
        cmdline+=" rd.luks.uuid=${uuid} rd.luks.options=${uuid}=tpm2-device=auto"
    fi

    # Add swapfile resume option if available
    if [[ -f "/swapfile" ]]; then
        cmdline+=" resume=UUID=$(findmnt -no UUID /) resume_offset=$(filefrag -v "/swapfile" 2>/dev/null | awk 'NR==4 {print $4}' | sed 's/\.$//')"
    fi

    echo "$cmdline"
}

# Create systemd-boot entry for both Root A and Root B
create_systemd_boot_entry() {
    echo "🔧 Creating systemd-boot entry..."
	TARGET_SUBVOL="$1"

	if [[ -z "$TARGET_SUBVOL" ]]; then
		echo "❌ Error: No target subvolume specified!"
		exit 1
	fi

	echo "🔧 Configuring Secure Boot for subvolume: $TARGET_SUBVOL"

	# Generate the boot entry for the specified subvolume
	cmdline=$(generate_cmdline "$TARGET_SUBVOL")

	cat <<EOF > "$BOOT_ENTRY_DIR/shani-os-$TARGET_SUBVOL.conf"
	title   Shani OS ($TARGET_SUBVOL)
	linux   /$KERNEL_IMAGE
	initrd  /$INITRAMFS_IMAGE
	options $cmdline
	EOF

	echo "✅ Boot entry created for $TARGET_SUBVOL."
}

# Main execution



# Main function to process command-line arguments and execute steps
main() {
	install_shim_and_mok
	copy_files_to_efi
	install_fwupd

    case "${1:-}" in
        configure)
            if [[ -z "${2:-}" ]]; then
                echo "❌ Missing subvolume name. Usage: $0 configure <subvol>"
                exit 1
            fi
            create_systemd_boot_entry "$2"
            enroll_mok
            bypass_mok_prompt
            echo -e "\n✅ Secure Boot setup complete! Reboot to enroll the MOK key."
            ;;
        *)
            echo "Usage: $0 configure <subvol>"
            exit 1
            ;;
    esac
}

echo "✅ Systemd-boot entry and boot files for Secure Boot setup have been completed."

