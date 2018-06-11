#!perl -w

use strict;

use Test::Most tests => 6;

BIN: {
	eval 'use Test::Script';
	if($@) {
		plan skip_all => 'Test::Script required for testing scripts';
	} else {
		SKIP: {
			if(-e 't/online.enabled') {
				script_compiles('bin/census');
			} else {
				if(!$ENV{AUTHOR_TESTING}) {
					diag('Author tests not required for installation');
					skip('Author tests not required for installation', 6);
				} else {
					script_compiles('bin/census');

					diag('Test requires Internet access');
					skip('Test requires Internet access', 5);
				}
			}

			script_runs(['bin/census']);

			ok(script_stdout_like(qr/\-77\.03/, 'test 1'));
			ok(script_stderr_is('', 'no error output'));
		}
	}
}
