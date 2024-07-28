import bluetooth, sys, os, stat
from time import sleep
from struct import pack,unpack
from obx_const import *

# substitute your mac's bd_addr here
MACADDR="AA:BB:CC:DD:EE:FF"
# alternatively write code to scan for stuff your mac is offering on
# bluetooth and fish out it's address
# bluetooth.find_service() should find "obex over l2cap" when obx_server
# is live at other end

psm=0x1001	# the psm on which obx_sever listens

def dump(data):
	n = len(data)
	print("len=",n)
	nib="0123456789abcdef"
	i=0
	while i<n:
		hex=""
		s=""
		k = i+16
		if k>n:  k=n
		while i < k:
			d = int(data[i])
			hi = d>>4
			lo = d & 0x0f;
			hex += nib[hi]
			hex += nib[lo]
			hex += ' '
			if d<0x20 or d>0x7e:  c ='.'
			else: c = chr(d)
			s += c
			i+=1
		print(hex, s)


# basic client that works with obx_server at other end
# handles limited subset of headers so may not work with other servers
# primitive error handling

class ObexClient(object):

	def __init__(self, bdaddr, psm):
		self.sock = bluetooth.BluetoothSocket(bluetooth.L2CAP)
		self.max_pkt_len = 672	# default L2CAP mtu
		print("connecting...")
		self.sock.connect((MACADDR, psm))
		print("ok")

	def connect(self):
		cnnct = b'\x80\00\07\x10\x00\x02\xa0'
		self.sock.send(cnnct)
		resp = self.sock.recv(self.max_pkt_len)
		#dump(resp)
		if len(resp)>=7 and resp[0] == 0xa0:
			print("obx connect ok")
			# remote max pkt len (big-endian) in resp[5..7]
			self.remote_max_pkt_len = resp[5]*256 + resp[6]
			print("rmpktlen=", self.remote_max_pkt_len)
		else:  print("obx connect failed")
		# note. there may be other headers.

	def get(self, filename, save=True):
		self.bytes_received=0
		hdr0 = self.name_header(filename)
		self.send_request(0x83, hdr0)
		self.data = self.sock.recv(self.max_pkt_len)
		#dump(self.data)
		status = self.parse_data()
		if save:  getfile = open(filename,"wb")
		if status & LENGTH_BIT:
			file_len = self.length
			print("len=",file_len)
		else:  file_len = 1024	# no length so restrict to 1k
		notdone = True
		while notdone:
			if status & (BODY_BIT | END_OF_BODY_BIT):
				bod_end = self.bod_start + self.bod_len
				bod = self.data[self.bod_start : bod_end]
				if save: getfile.write(bod)
				else:  print(str(bod,'utf-8'))
				self.bytes_received += self.bod_len
				# complete when end_of_bod or bytes_received==file_len
				notdone =  not ((status & END_OF_BODY_BIT) or self.bytes_received >= file_len)
				if notdone:	# get more
					self.sock.send(self.req)
					self.data=self.sock.recv(self.max_pkt_len)
					status = self.parse_data()
				else:
					if save:  getfile.close()
					print("get complete")

			else:  print("what? no body");  break

	def put(self, filename):
		file_len = os.stat(filename)[stat.ST_SIZE]
		#print("file_len=", file_len)
		putfile = open(filename, 'rb')
		bytes_read=0
		hdr0 = self.name_header(filename)
		hdr1 = self.length_header(file_len)
		notdone = True
		while notdone:
			buff = putfile.read(512)
			bufflen = len(buff)
			bytes_read += bufflen
			endof = (bytes_read >= file_len)
			hdr2 = self.body_header(buff, endof)
			self.send_request(0x82, hdr0+hdr1+hdr2)
			resp = self.sock.recv(self.max_pkt_len)
			if not(resp[0] == 0x90 or resp[0] == 0xa0):
				print("something wrong")
				break
			notdone = not endof
		putfile.close()
		if resp[0]==0xa0:  print("put complete")

	def setpath(self, pathname, goto_parent=0):
		if pathname:
			hdr0 = self.name_header(pathname)
			l = len(hdr0) + 5
			req = pack('>BHBB', 0x85, l , goto_parent, 0) + hdr0
		else :
			req =  b'\x85\x00\x05' + pack('BB', goto_parent, 0)
		self.sock.send(req)
		resp = self.sock.recv(self.max_pkt_len)
		if resp[0] == 0xa0:  print("setpath ok")

	def name_header(self, filename):
		u = bytes(filename,'utf-16-be') + b'\x00\x00'
		#print(u)
		hid = NAME_HDR | UNICODE
		l = len(u)+3
		hdr = pack('>BH', hid, l) + u
		return hdr

	def length_header(self, len):
		hid = LENGTH_HDR | FOURBYTE
		hdr = pack('>BI', hid, len)
		return hdr

	def body_header(self, buff, endof):
		if endof :  hid = END_OF_BODY_HDR | BITES
		else:  hid = BODY_HDR | BITES
		hdr = pack('>BH', hid, len(buff)+3) + buff
		return hdr

	# to send several headers, concatenate a la
	# obxcli.send_request(opcode, hdr0 + hdr1 + ...)
	def send_request(self, opcode, hdrs):
		l = len(hdrs)+3		# total length
		if l > self.remote_max_pkt_len:
			print("ERROR.  remote_max_pkt_len exceded")
			# should handle gracefully
		self.req = pack('>BH', opcode, l) + hdrs
		self.sock.send(self.req)

	def parse_data(self):
		if self.data[0] == 0xa0:	# if success
			status=0
			k=3
			left=len(self.data)-3
			while left>0:
				hid = self.data[k]
				typebits = hid & 0xc0
				hid &= 0x3f
				if hid == NAME_HDR:
					l16 = self.ntohs(k+1)
					self.name = str(self.data[k+3: k+l16],'utf-16-be')
					status |= NAME_BIT
					k+=l16;  left-=l16
					#print("l16=", l16)
				elif hid == LENGTH_HDR:
					self.length= self.ntohl(k+1)
					status |= LENGTH_BIT
					k+=5;  left-=5
					#print(self.length)
				elif (hid == BODY_HDR) or (hid == END_OF_BODY_HDR):
					self.bod_start = k+3
					l16 = self.ntohs(k+1)
					self.bod_len = l16-3
					if hid==END_OF_BODY_HDR:  status |= END_OF_BODY_BIT
					else:  status |= BODY_BIT
					k+=l16;  left-=l16
				else:
					print(lookup[hid], "header IGNORED")
					if (typebits == UNICODE) or (typebits == BITES):
						l16 = self.ntohs(k+1)
						k+=l16;  left-=l16
					elif typebits == FOURBYTES:
						k+=5;  left-=5
					else :
						k+=2;  left-=2
			return status
		else:
			print("no good")
			return FORBIDDEN_BIT

	def ntohs(self, k):	# 16 bit field len
		return self.data[k]*256 + self.data[k+1]

	def ntohl(self, k):	# 32 bit value
		q, = unpack('>I',self.data[k:k+4])
		return q

	def disconnect(self):
		self.sock.send(b'\x81\x00\x03')
		resp = self.sock.recv(self.max_pkt_len)
		if resp[0]==0xa0:  print("disconnect ok")
		self.sock.close()
		self.sock=None

if len(sys.argv)==2:
	filename = sys.argv[1]
else:
	print("usage: python obxget.py <filename>")
	quit()

obxcli = ObexClient(MACADDR,psm)
sleep(0.2)
obxcli.connect()
sleep(0.2)
obxcli.get(filename)

# to upload: obxcli.put(filename)   file should be on working dir
# obx_server can provide dir listing:
# try obxcli.get(dir_path, False)  when save==False  output is to screen, not file
# dir_path is relative to base path that obx_server uses
sleep(0.2)
obxcli.disconnect()
