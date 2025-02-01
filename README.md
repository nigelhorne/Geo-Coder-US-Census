[![Kritika Analysis Status](https://kritika.io/users/nigelhorne/repos/7736847150242974/heads/master/status.svg)](https://kritika.io/users/nigelhorne/repos/7736847150242974/heads/master/)
[![Linux Build Status](https://travis-ci.org/nigelhorne/Geo-Coder-US-Census.svg?branch=master)](https://travis-ci.org/nigelhorne/Geo-Coder-US-Census)

# NAME

Geo::Coder::US::Census - Provides a Geo-Coding functionality for the US using [https://geocoding.geo.census.gov](https://geocoding.geo.census.gov)

# VERSION

Version 0.07

# SYNOPSIS

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

# DESCRIPTION

Geo::Coder::US::Census provides geocoding functionality specifically for U.S. addresses by interfacing with the U.S. Census Bureau's geocoding service.
It allows developers to convert street addresses into geographical coordinates (latitude and longitude) by querying the Census Bureau's API.
Using [LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent) (or a user-supplied agent), the module constructs and sends an HTTP GET request to the API.

The module uses [Geo::StreetAddress::US](https://metacpan.org/pod/Geo%3A%3AStreetAddress%3A%3AUS) to break down a given address into its components (street, city, state, etc.),
ensuring that the necessary details for geocoding are present.

- Caching

    Identical geocode requests are cached (using [CHI](https://metacpan.org/pod/CHI) or a user-supplied caching object),
    reducing the number of HTTP requests to the API and speeding up repeated queries.

    This module leverages [CHI](https://metacpan.org/pod/CHI) for caching geocoding responses.
    When a geocode request is made,
    a cache key is constructed from the complete query URL.
    If a cached response exists,
    it is returned immediately,
    avoiding unnecessary API calls.

- Rate-Limiting

    A minimum interval between successive API calls can be enforced to ensure that the Census API is not overwhelmed and to comply with any request throttling requirements.

    Rate-limiting is implemented using [Time::HiRes](https://metacpan.org/pod/Time%3A%3AHiRes).
    A minimum interval between API
    calls can be specified via the `min_interval` parameter in the constructor.
    Before making an API call,
    the module checks how much time has elapsed since the
    last request and,
    if necessary,
    sleeps for the remaining time.

# METHODS

## new

    $geo_coder = Geo::Coder::US::Census->new(%options);

Creates a new instance of the geocoder. Acceptable options include:

- `ua`

    An object to use for HTTP requests.
    If not provided, a default user agent is created.

- `host`

    The API host endpoint.
    Defaults to [https://geocoding.geo.census.gov/geocoder/locations/address](https://geocoding.geo.census.gov/geocoder/locations/address).

- `cache`

    A caching object.
    If not provided,
    an in-memory cache is created with a default expiration of one hour.

- `min_interval`

    Minimum number of seconds to wait between API requests.
    Defaults to `0` (no delay).
    Use this option to enforce rate-limiting.

    $geo_coder = Geo::Coder::US::Census->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $geo_coder = Geo::Coder::US::Census->new(ua => $ua);

## geocode

Geocode an address.
It accepts addresses provided in various forms -
whether as a single argument, a key/value pair, or within a hash reference -
making it easy to integrate into different codebases.
It decodes the JSON response from the API using [JSON::MaybeXS](https://metacpan.org/pod/JSON%3A%3AMaybeXS),
providing the result as a hash.
This allows easy extraction of latitude, longitude, and other details returned by the service.

    $location = $geo_coder->geocode(location => $location);
    # @location = $geo_coder->geocode(location => $location);

    print 'Latitude: ', $location->{'latt'}, "\n";
    print 'Longitude: ', $location->{'longt'}, "\n";

- A hash (or hash reference) with a key `location`.
- A single string argument (which is assumed to be the location).

Before sending the query, the address is:

- Converted to UTF-8 if necessary
- Cleaned by removing trailing country names (e.g., "United States", "US", "USA")
- Parsed using [Geo::StreetAddress::US](https://metacpan.org/pod/Geo%3A%3AStreetAddress%3A%3AUS) to extract key components (e.g., street, city, state)

## ua

Accessor method to get and set UserAgent object used internally. You
can call _env\_proxy_ for example, to get the proxy information from
environment variables:

    $geo_coder->ua()->env_proxy(1);

You can also set your own User-Agent object:

    $geo_coder->ua(LWP::UserAgent::Throttled->new());

## reverse\_geocode

    # $location = $geo_coder->reverse_geocode(latlng => '37.778907,-122.39732');

\# Similar to geocode except it expects a latitude/longitude parameter.

Reverse geocoding is not supported by this module.
Calling this method will immediately throw an exception.

## run

In addition to being used as a library within other Perl scripts,
[Geo::Coder::US::Census](https://metacpan.org/pod/Geo%3A%3ACoder%3A%3AUS%3A%3ACensus) can be run directly from the command line.
When invoked this way,
it accepts an address as input,
performs geocoding,
and prints the resulting data structure via [Data::Dumper](https://metacpan.org/pod/Data%3A%3ADumper).

    perl Census.pm 1600 Pennsylvania Avenue NW, Washington DC

This method allows the module to be executed as a standalone script from the command line.
It will:

- Join command-line arguments into a single address string
- Create a new geocoder instance and attempt to geocode the address
- Die with an error message if geocoding fails
- Dump the resulting data structure to STDOUT using [Data::Dumper](https://metacpan.org/pod/Data%3A%3ADumper)

# AUTHOR

Nigel Horne <njh@bandsman.co.uk>

Based on [Geo::Coder::GooglePlaces](https://metacpan.org/pod/Geo%3A%3ACoder%3A%3AGooglePlaces).

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at geocoding.geo.census.gov.

# BUGS

Please report any bugs or feature requests to the author.
This module is provided as-is without any warranty.

# SEE ALSO

[Geo::Coder::GooglePlaces](https://metacpan.org/pod/Geo%3A%3ACoder%3A%3AGooglePlaces), [HTML::GoogleMaps::V3](https://metacpan.org/pod/HTML%3A%3AGoogleMaps%3A%3AV3)

[https://www.census.gov/data/developers/data-sets/Geocoding-services.html](https://www.census.gov/data/developers/data-sets/Geocoding-services.html)

# LICENSE AND COPYRIGHT

Copyright 2017-2025 Nigel Horne.

This program is released under the following licence: GPL2
