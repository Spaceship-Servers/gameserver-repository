#!/usr/bin/python3


"""
Finds the location of strings and patches the first character to the null terminator,
preventing the messages from being displayed in the server console.

This can be executed while the server is running (on Linux; may not be successful on Windows).
"""

import argparse
import ast
import configparser
import mmap
import os

def patch_to_null(mbin, target, fully_zero = True):
	mbin.seek(0)
	offset = mbin.find(target.encode('ascii'))
	if offset == -1:
		return False
	mbin.seek(offset)
	# read up to the next null terminator and zero out the range if we fullclear it
	mbin.write(b'\0' * (mbin.find(b'\0', offset) - offset if fully_zero else 1))
	return True

if __name__ == '__main__':
	parser = argparse.ArgumentParser(
			description = "Patches various strings out of the given binary")
	
	parser.add_argument('binary', help = "Binary file to patch", type = argparse.FileType(mode = 'rb+'))
	parser.add_argument('-c', '--config', help = "List of files / strings to match",
			action = 'append')
	
	args = parser.parse_args()
	
	mbin = mmap.mmap(args.binary.fileno(), length = 0, access = mmap.ACCESS_WRITE)
	
	config = configparser.ConfigParser(converters = {
		# return multiline value as an evaluated Python literal
		'pyliteral': ast.literal_eval,
	}, interpolation = None)
	config.read([ "str0.ini" ] + args.config, encoding = "utf8")
	
	for target in config.getpyliteral(os.path.basename(args.binary.name), "strings"):
		fully_zero = config.getboolean(os.path.basename(args.binary.name), "fully_zero", fallback = False)
		if not patch_to_null(mbin, target, fully_zero):
			print(f'{args.binary.name}: Failed to locate string "{target}"')
	mbin.flush()
