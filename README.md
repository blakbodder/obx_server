#obx_server

obex over L2CAP bluetooth.  server uses IOBluetooth.
python client tested on rasberry pi.

macOS <-> raspberry pi file transfer.

mac requirements:
macOS (tested on 10.15.7) 
xcode (author used 11.7)

pi requirements:
a model with bluetooth
python 3.x
pybluez

compile obx_server with xcode (maybe need change build settings such as install owner).
ensure devices are near each other
switch bluetooth on (mac and pi)
no need to pair but might get connection-request-pop-up.

modify obxget.py line 7:
MACADDR = "AA:BB:CC:DD:EE:FF"
so that the bd_addr is that of your mac
obxget.py needs obx_const.py

you can find nearby devices using hcitool on pi.
to find your mac's bdaddr do:  hcitool scan
in the raspberry pi terminal.
bluetoothctl can also be used to find bt devices. 

you may need to change some settings on the mac: firewall, file sharing, bluetooth sharing
run obx_server
when you see
service L2CAP chan psm = 0x1001
do python obxget.py <filename_to_get> at the raspberry end.
a pop-up might appear, asking permission to access a directory.

note this is a rudimentary obex ftp that does not comply with the SIG standard.
