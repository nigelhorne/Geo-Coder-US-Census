#!perl -w

use strict;

use Test::Most tests => 6;
use Test::Script;

script_compiles('bin/census');

BIN: {
	SKIP: {
		skip 'Test requires Internet access', 5 unless(-e 't/online.enabled');

		script_runs(['bin/census']);

		ok(script_stdout_like(qr/\-77\.03/, 'test 1'));
		ok(script_stderr_is('', 'no error output'));
	}
}
