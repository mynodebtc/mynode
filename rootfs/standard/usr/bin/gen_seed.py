#!/usr/local/bin/python3
from lnd_grpc import lnd_grpc
import os

def format_seed_numbered(seed):
	formatted_seed = ""
	count = 1
	for word in seed:
		formatted_seed += "{}: {}\n".format(count, word)
		count += 1

	return formatted_seed.rstrip()

def format_seed_raw(seed):
	s = ""
	for word in seed:
		s += word + " "
	return s.rstrip()

# This is the main entry point for the program
if __name__ == "__main__":

    network="mainnet"
    if os.path.isfile("/mnt/hdd/mynode/settings/.testnet_enabled"):
        network="testnet"

    # Generate the seed
    rpc = lnd_grpc.Client(lnd_dir="/home/bitcoin/.lnd/",
                          macaroon_path="/home/bitcoin/.lnd/data/chain/bitcoin/{}/admin.macaroon".format(network))

    # Get seed and print
    data = rpc.gen_seed()
    formatted_seed = format_seed_raw(data.cipher_seed_mnemonic)
    print(formatted_seed)