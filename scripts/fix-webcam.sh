#!/bin/bash
# Fix webcam after suspend

echo "Resetting USB controller (PCI c4:00.4)..."
sudo bash -c 'echo 1 > /sys/bus/pci/devices/0000:c4:00.4/remove'
sleep 2
sudo bash -c 'echo 1 > /sys/bus/pci/rescan'
sleep 2

# Check if camera appeared
if [ -e /dev/video0 ]; then
    echo "Webcam restored:"
    v4l2-ctl --list-devices 2>/dev/null | head -10
else
    echo "Camera still not detected. Try rebooting."
fi
