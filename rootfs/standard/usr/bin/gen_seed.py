#!/usr/local/bin/python3
import base64, codecs, json, requests
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
    REST_GEN_SEED_URL="https://localhost:10080/v1/genseed"
    REST_CERT_PATH="/home/bitcoin/.lnd/tls.cert"

    # Generate the seed
    r = requests.get(REST_GEN_SEED_URL, verify=REST_CERT_PATH)
    data = r.json()
    formatted_seed = format_seed_raw( data['cipher_seed_mnemonic'] )
    print(formatted_seed)