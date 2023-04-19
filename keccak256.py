from Crypto.Hash import keccak
import sys

with open(sys.argv[1],"rb") as f:
   k = keccak.new(digest_bits=256)
   bytes = f.read()
   k.update(bytes)
   print (k.hexdigest())