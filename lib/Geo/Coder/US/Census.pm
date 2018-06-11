package Geo::Coder::US::Census;

use strict;
use warnings;

use Carp;
use Encode;
use JSON;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::https;
use URI;
use Geo::StreetAddress::US;

=head1 NAME

Geo::Coder::US::Census - Provides a Geo-Coding functionality for the US using L<https://geocoding.geo.census.gov>

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';

=head1 SYNOPSIS

      use Geo::Coder::US::Census;

      my $geo_coder = Geo::Coder::US::Census->new();
      my $location = $geo_coder->geocode(location => '4600 Silver Hill Rd., Suitland, MD');
      # Sometimes the server gives a 500 error on this
      $location = $geo_coder->geocode(location => '4600 Silver Hill Rd., Suitland, MD, USA');

=head1 DESCRIPTION

Geo::Coder::US::Census provides an interface to geocoding.geo.census.gov.  Geo::Coder::US no longer seems to work.

=head1 METHODS

=head2 new

    $geo_coder = Geo::Coder::US::Census->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $geo_coder = Geo::Coder::US::Census->new(ua => $ua);

=cut

sub new {
	my($class, %param) = @_;

	my $ua = delete $param{ua} || LWP::UserAgent->new(agent => __PACKAGE__ . "/$VERSION");
	my $host = delete $param{host} || 'geocoding.geo.census.gov/geocoder/locations/address';

	return bless { ua => $ua, host => $host }, $class;
}

=head2 geocode

    $location = $geo_coder->geocode(location => $location);
    # @location = $geo_coder->geocode(location => $location);

    print 'Latitude: ', $location->{'latt'}, "\n";
    print 'Longitude: ', $location->{'longt'}, "\n";

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
	if($location =~ /^(\d+\s+[\w\s]+),\s*([\w\s]+),\s*[\w\s]+,\s*([A-Za-z]+)$/) {
		$location = "$1, $2, $3";
	}

	my $uri = URI->new("https://$self->{host}");
	$location =~ s/\s/+/g;
	my $hr = Geo::StreetAddress::US->parse_address($location);

	my %query_parameters = ('format' => 'json', 'benchmark' => 'Public_AR_Current');
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
	$query_parameters{'city'} = $hr->{'city'};
	$query_parameters{'state'} = $hr->{'state'};

	$uri->query_form(%query_parameters);
	my $url = $uri->as_string();

	my $res = $self->{ua}->get($url);

	if($res->is_error()) {
		Carp::croak("$url API returned error: " . $res->status_line());
		return;
	}

	my $json = JSON->new->utf8();
	return $json->decode($res->content());

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

Not supported.

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
	Carp::croak('Reverse geocode is not supported');
}

=head2 run

You can also run this module from the command line:

    perl Census.pm 1600 Pennsylvania Avenue NW, Washington DC

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

Based on L<Geo::Coder::Coder::Googleplaces>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at geocoding.geo.census.gov.

=head1 BUGS

Should be called Geo::Coder::NA for North America.

=head1 SEE ALSO

L<Geo::Coder::GooglePlaces>, L<HTML::GoogleMaps::V3>

https://www.census.gov/data/developers/data-sets/Geocoding-services.html

=head1 LICENSE AND COPYRIGHT

Copyright 2017,2018 Nigel Horne.

This program is released under the following licence: GPL2

=cut

1;
