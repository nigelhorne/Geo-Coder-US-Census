package Geo::Coder::US::Census;

use strict;
use warnings;

use Carp;
use CHI;
use Encode;
use Geo::StreetAddress::US;
use JSON::MaybeXS;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::https;
use Time::HiRes;
use URI;

=head1 NAME

Geo::Coder::US::Census - Provides a Geo-Coding functionality for the US using L<https://geocoding.geo.census.gov>

=head1 VERSION

Version 0.07

=cut

our $VERSION = '0.07';

=head1 SYNOPSIS

  use Geo::Coder::US::Census;
  use CHI;

  # Create a cache object (here, an in-memory cache)
  my $cache = CHI->new(
      driver => 'Memory',
      global => 1,
      expires_in => '1 hour',
  );

  # Instantiate the geocoder with a custom User Agent, cache, and a minimum interval between API calls.
  my $geo_coder = Geo::Coder::US::Census->new(
      ua     => LWP::UserAgent->new(agent => 'MyApp/1.0'),
      cache    => $cache,
      min_interval => 1,    # Minimum interval of 1 second between API calls
  );

  # Get geocoding results (as a hash decoded from JSON)
  my $result = $geo_coder->geocode(location => "4600 Silver Hill Rd., Suitland, MD");

  if($result) {
      # Access latitude and longitude from the API response (structure may vary)
      print 'Latitude: ', $result->{result}{addressMatches}[0]{coordinates}{x}, "\n";
      print 'Longitude: ', $result->{result}{addressMatches}[0]{coordinates}{y}, "\n";
  }

  # Sometimes the server gives a 500 error on this
  $location = $geo_coder->geocode(location => '4600 Silver Hill Rd., Suitland, MD, USA');

  # Note: Reverse geocoding is not supported.

  # The module can also be executed from the command line:
  #   perl Geo/Coder/US/Census.pm "1600 Pennsylvania Avenue NW, Washington, DC"

=head1 DESCRIPTION

Geo::Coder::US::Census provides geocoding functionality specifically for U.S. addresses by interfacing with the U.S. Census Bureau's geocoding service.
It allows developers to convert street addresses into geographical coordinates (latitude and longitude) by querying the Census Bureau's API.
Using L<LWP::UserAgent> (or a user-supplied agent), the module constructs and sends an HTTP GET request to the API.

The module uses L<Geo::StreetAddress::US> to break down a given address into its components (street, city, state, etc.),
ensuring that the necessary details for geocoding are present.

=over 4

=item * Caching

Identical geocode requests are cached (using L<CHI> or a user-supplied caching object),
reducing the number of HTTP requests to the API and speeding up repeated queries.

This module leverages L<CHI> for caching geocoding responses.
When a geocode request is made,
a cache key is constructed from the request.
If a cached response exists,
it is returned immediately,
avoiding unnecessary API calls.

=item * Rate-Limiting

A minimum interval between successive API calls can be enforced to ensure that the Census API is not overwhelmed and to comply with any request throttling requirements.

Rate-limiting is implemented using L<Time::HiRes>.
A minimum interval between API
calls can be specified via the C<min_interval> parameter in the constructor.
Before making an API call,
the module checks how much time has elapsed since the
last request and,
if necessary,
sleeps for the remaining time.

=back

=head1 METHODS

=head2 new

  $geo_coder = Geo::Coder::US::Census->new(%options);

Creates a new instance of the geocoder. Acceptable options include:

=over 4

=item * C<ua>

An object to use for HTTP requests.
If not provided, a default user agent is created.

=item * C<host>

The API host endpoint.
Defaults to L<https://geocoding.geo.census.gov/geocoder/locations/address>.

=item * C<cache>

A caching object.
If not provided,
an in-memory cache is created with a default expiration of one hour.

=item * C<min_interval>

Minimum number of seconds to wait between API requests.
Defaults to C<0> (no delay).
Use this option to enforce rate-limiting.

=back

    $geo_coder = Geo::Coder::US::Census->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $geo_coder = Geo::Coder::US::Census->new(ua => $ua);

=cut

sub new {
	my $class = $_[0];

	shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $ua = $args{ua};
	if(!defined($ua)) {
		$ua = LWP::UserAgent->new(agent => __PACKAGE__ . "/$VERSION");
		$ua->default_header(accept_encoding => 'gzip,deflate');
		$ua->env_proxy(1);
	}
	my $host = $args{host} || 'geocoding.geo.census.gov/geocoder/locations/address';

	# Set up caching (default to an in-memory cache if none provided)
	my $cache = $args{cache} || CHI->new(
		driver => 'Memory',
		global => 1,
		expires_in => '1 day',
	);

	# Set up rate-limiting: minimum interval between requests (in seconds)
	my $min_interval = $args{min_interval} || 0;	# default: no delay

	return bless {
		ua => $ua,
		host => $host,
		cache => $cache,
		min_interval => $min_interval,
		last_request => 0,	# Initialize last_request timestamp
		%args,
	}, $class;
}

=head2 geocode

Geocode an address.
It accepts addresses provided in various forms -
whether as a single argument, a key/value pair, or within a hash reference -
making it easy to integrate into different codebases.
It decodes the JSON response from the API using L<JSON::MaybeXS>,
providing the result as a hash.
This allows easy extraction of latitude, longitude, and other details returned by the service.

    $location = $geo_coder->geocode(location => $location);
    # @location = $geo_coder->geocode(location => $location);

    print 'Latitude: ', $location->{'latt'}, "\n";
    print 'Longitude: ', $location->{'longt'}, "\n";

=over 4

=item * A hash (or hash reference) with a key C<location>.

=item * A single string argument (which is assumed to be the location).

=back

Before sending the query, the address is:

=over 4

=item * Converted to UTF-8 if necessary

=item * Cleaned by removing trailing country names (e.g., "United States", "US", "USA")

=item * Parsed using L<Geo::StreetAddress::US> to extract key components (e.g., street, city, state)

=back

=cut

sub geocode {
	my $self = shift;
	my %param;

	if(ref($_[0]) eq 'HASH') {
		%param = %{$_[0]};
	} elsif(ref($_[0])) {
		Carp::croak('Usage: geocode(location => $location)');
	} elsif(@_ % 2 == 0) {
		%param = @_;
	} else {
		$param{location} = shift;
	}

	my $location = $param{location}
		or Carp::croak('Usage: geocode(location => $location)');

	if (Encode::is_utf8($location)) {
		$location = Encode::encode_utf8($location);
	}

	if($location =~ /,?(.+),\s*(United States|US|USA)$/i) {
		$location = $1;
	}

	# Remove county from the string, if that's included
	# Assumes not more than one town in a state with the same name
	# in different counties - but the census Geo-Coding doesn't support that
	# anyway
	# Some full state names include spaces, e.g South Carolina
	# Some roads include full stops, e.g. S. West Street
	if($location =~ /^(\d+\s+[\w\s\.]+),\s*([\w\s]+),\s*[\w\s]+,\s*([A-Za-z\s]+)$/) {
		$location = "$1, $2, $3";
	}

	my $uri = URI->new("https://$self->{host}");
	my $hr = Geo::StreetAddress::US->parse_address($location);

	if((!defined($hr->{'city'})) || (!defined($hr->{'state'}))) {
		# use Data::Dumper;
		# print Data::Dumper->new([$hr])->Dump(), "\n";
		Carp::carp(__PACKAGE__ . ": city and state are mandatory ($location)");
		return;
	}

	my %query_parameters = (
		'benchmark' => 'Public_AR_Current',
		'city' => $hr->{'city'},
		'format' => 'json',
		'state' => $hr->{'state'},
	);
	if($hr->{'street'}) {
		if($hr->{'number'}) {
			$query_parameters{'street'} = $hr->{'number'} . ' ' . $hr->{'street'} . ' ' . $hr->{'type'};
		} else {
			$query_parameters{'street'} = $hr->{'street'} . ' ' . $hr->{'type'};
		}
		if($hr->{'suffix'}) {
			$query_parameters{'street'} .= ' ' . $hr->{'suffix'};
		}
	}

	$uri->query_form(%query_parameters);
	my $url = $uri->as_string();

	# Create a cache key based on the location (might want to use a stronger hash function if needed)
	my $cache_key = "geocode:$location";
	if(my $cached = $self->{cache}->get($cache_key)) {
		return $cached;
	}

	# Enforce rate-limiting: ensure at least min_interval seconds between requests.
	my $now = time();
	my $elapsed = $now - $self->{last_request};
	if($elapsed < $self->{min_interval}) {
		Time::HiRes::sleep($self->{min_interval} - $elapsed);
	}
	my $res = $self->{ua}->get($url);

	# Update last_request timestamp
	$self->{last_request} = time();

	if($res->is_error()) {
		Carp::carp("$url API returned error: " . $res->status_line());
		return;
	}

	my $json = JSON::MaybeXS->new->utf8();
	my $data = $json->decode($res->decoded_content());

	# Cache the result before returning it
	$self->{cache}->set($cache_key, $data);

	return $data;

	# my @results = @{ $data || [] };
	# wantarray ? @results : $results[0];
}

=head2 ua

Accessor method to get and set UserAgent object used internally. You
can call I<env_proxy> for example, to get the proxy information from
environment variables:

  $geo_coder->ua()->env_proxy(1);

You can also set your own User-Agent object:

  $geo_coder->ua(LWP::UserAgent::Throttled->new());

=cut

sub ua {
	my $self = shift;
	if (@_) {
		$self->{ua} = shift;
	}
	$self->{ua};
}

=head2 reverse_geocode

    # $location = $geo_coder->reverse_geocode(latlng => '37.778907,-122.39732');

# Similar to geocode except it expects a latitude/longitude parameter.

Reverse geocoding is not supported by this module.
Calling this method will immediately throw an exception.

=cut

sub reverse_geocode {
	# my $self = shift;

	# my %param;
	# if (@_ % 2 == 0) {
		# %param = @_;
	# } else {
		# $param{latlng} = shift;
	# }

	# my $latlng = $param{latlng}
		# or Carp::croak("Usage: reverse_geocode(latlng => \$latlng)");

	# return $self->geocode(location => $latlng, reverse => 1);
	Carp::croak(__PACKAGE__, ': Reverse geocode is not supported');
}

=head2 run

In addition to being used as a library within other Perl scripts,
L<Geo::Coder::US::Census> can be run directly from the command line.
When invoked this way,
it accepts an address as input,
performs geocoding,
and prints the resulting data structure via L<Data::Dumper>.

    perl Census.pm 1600 Pennsylvania Avenue NW, Washington DC

This method allows the module to be executed as a standalone script from the command line.
It will:

=over 4

=item * Join command-line arguments into a single address string

=item * Create a new geocoder instance and attempt to geocode the address

=item * Die with an error message if geocoding fails

=item * Dump the resulting data structure to STDOUT using L<Data::Dumper>

=back

=cut

__PACKAGE__->run(@ARGV) unless caller();

sub run {
	require Data::Dumper;

	my $class = shift;

	my $location = join(' ', @_);

	my @rc = $class->new()->geocode($location);

	die "$0: geocoding failed" unless(scalar(@rc));

	print Data::Dumper->new([\@rc])->Dump();
}

=head1 AUTHOR

Nigel Horne <njh@bandsman.co.uk>

Based on L<Geo::Coder::GooglePlaces>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at geocoding.geo.census.gov.

=head1 BUGS

Please report any bugs or feature requests to the author.
This module is provided as-is without any warranty.

=head1 SEE ALSO

L<Geo::Coder::GooglePlaces>, L<HTML::GoogleMaps::V3>

L<https://www.census.gov/data/developers/data-sets/Geocoding-services.html>

=head1 LICENSE AND COPYRIGHT

Copyright 2017-2025 Nigel Horne.

This program is released under the following licence: GPL2

=cut

1;
