# NAME

Net::Magallanes - encapsulation of API calls to RIPE Atlas project.

# SYNOPSIS

    use Net::Magallanes;

    my $atlas = new Net::Magallanes (
        KEY => '<YOUR_API_KEY>'
    );

    my $msm_id = $atlas->dns(
        name    =>  'www.vulcano.cl',
        type    =>  'A',
    );

    # Wait for RIPE Atlas to complete
    sleep(120);

    my @result = $atlas->answers($msm_id, 'A');
    print "Result is ", join ',', @result;

# DESCRIPTION

Net::Magallanes is a pure perl interface to the RIPE Atlas API,
for requesting measurements and getting data from past measurements.

More information on RIPE Atlas platform: atlas.ripe.net

# METHODS

## new

Creates a new Net::Magallanes object. There're two optional
parameters:

   KEY => '<Secret API Key for RIPE Atlas>'

If you want to create new measurements, you must provide an API
key for your RIPE Atlas account.

   INFILES => '<path/filename>[,<morefiles>]'

If you want to use an existing JSON file with a previous measurement,
instead of downloading one from Atlas API site. You can use more than
one file, comma separated.

## answers(<MSM-id> [, <qtype>])

Get an array of answers from the previous measurement with id MSM-id.
The "answers" are the records from the ANSWER section of a DNS
measurement.

If you specify a qtype 'A' (default) or 'AAAA', you'll get an array of
addresses from the corresponding answer. With other types you'll get an
array with a printable representation of each answer.


## nsids(<MSM-id>)

Get an array of NSID texts from the results of a previous measurement
MSM-id.

If there's no NSID for a result, you'll get a 'NULL' string.


## rcodes

Get an array of RCODE texts from the results of a previous measurement
MSM-id.


## dns( name => '<QNAME>' [, type => '<QTYPE>'] [, num_prb => '<NUM_PROBES'> ])

Create a new "one-off" DNS measurement, asking for the name <QNAME>
(required) and type <QTYPE> (AAAA default), from <NUM_PROBES> (default
5) probes at random, with worldwide coverage.

You must had initialized the Net::Magallanes object with a valid API
key, with enough permissions and credits for measurement creation.

Return the measurement id assignated by Atlas platform.

You should take care for waiting enough time (5~6 minutes) before
asking for the results of this measurement.

The measurement uses sensible parameters like DO bit set, 1232 EDNS
buffer size, recursive towards the probe resolver, etc.


# AUTHOR

Hugo Salgado <hsalgado@vulcano.cl>

# COPYRIGHT

Copyright 2021- Hugo Salgado

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO
