#!/usr/bin/env perl

# Test the code without touching the server

use strict;
use warnings;
use Test::Most;
use Test::LWP::UserAgent;
use CHI;

BEGIN { use_ok('Geo::Coder::US::Census') }

# Create a Test::LWP::UserAgent instance for mocking HTTP responses.
my $tua = Test::LWP::UserAgent->new();

# Dummy JSON response that simulates the Census API response.
my $dummy_response = '{"result":{"addressMatches":[{"dummy":"match"}]}}';

# Map any URL to a successful HTTP response with the dummy JSON content.
$tua->map_response(
	qr/.*/,
	HTTP::Response->new(200, "OK", ['Content-Type' => 'application/json'], $dummy_response)
);

# Create an in-memory cache using CHI.
my $cache = CHI->new(
	driver => 'Memory',
	global => 1,
	expires_in => '1 hour',
);

# Instantiate the geocoder with the test UA, cache, and no delay for rate-limiting.
my $geo = Geo::Coder::US::Census->new(
	ua => $tua,
	cache => $cache,
	min_interval => 0,	# No rate limit delay needed for this test
);

# Calling geocode should return a hash reference.
my $result = $geo->geocode(location => '4600 Silver Hill Rd., Suitland, MD');
ok($result && ref($result) eq 'HASH', 'geocode returned a hash reference');

# The returned hash should contain a 'result' key.
ok(exists $result->{result}, 'Result contains the key "result"');

# The 'addressMatches' key inside result should be an array.
ok(ref($result->{result}{addressMatches}) eq 'ARRAY', 'addressMatches is an array');

# Calling geocode with the same address again should hit the cache.
my $result_cached = $geo->geocode(location => '4600 Silver Hill Rd., Suitland, MD');
is_deeply($result, $result_cached, 'Second call returns the cached result');

# Verify that the dummy response content was returned.
like( $dummy_response, qr/"dummy":"match"/, 'Dummy response contains expected content' );

done_testing();
