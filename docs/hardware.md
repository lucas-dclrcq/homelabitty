# Hardware

## Dell Optiplex 3080/3090

### Troubleshooting

#### On boot it keeps showing a black PXE screen

Go in the BIOS and disable the NICs in the boot order menu

#### NVMe is not listed in talosctl disks

Disable the raid mode in the bios and choose AHCI
