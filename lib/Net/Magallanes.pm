package Net::Magallanes;

use strict;
use 5.008_005;
our $VERSION = '0.01';

use LWP::UserAgent;
use JSON;
use MIME::Base64;
use Net::DNS;
use Carp;

sub new {
    my $this = shift;
    my %params = @_;

    my ($API_KEY, $IN_FILES);
    my $API_BASE = 'https://atlas.ripe.net/api/v2';

    my $class = ref($this) || $this;

    $API_KEY = $params{'KEY'} if $params{'KEY'};
    $IN_FILES = $params{'INFILES'} if $params{'INFILES'};

    # armar estructura con defaults sensibles
    my $self = {};
    bless $self, $class;

    # Si no hay KEY igual le damos, pero no podremos crear cosas, solo
    # consultar.
    $self->{'KEY'} = $API_KEY;
    $self->{'ua'}  = LWP::UserAgent->new(timeout => 10);
    $self->{'ua'}->default_header('Content-Type' => 'application/json');
    $self->{'ua'}->default_header('Accept' => 'application/json');
    $self->{'URL'} = $API_BASE;

    $self->{'_CACHE_MSM'} = {};

    if ($IN_FILES) {
        my @files = split ',', $IN_FILES;
        my $data;
        foreach my $file (@files) {
            open my $fh, '<', $file
                or croak "Couldn't open file $file: $!";
            local $/ = undef;
            $data = <$fh>;
            close $fh;
            my $result = decode_json $data;
            my $mi = $result->[0]->{msm_id};
            $self->{'_CACHE_MSM'}->{$mi} = $result;
        }
    }

    # Qué puede venir:
    # timeouts de https request
    # versión de API
    # defaults comunes a todo:
    #   - one_off (default true)

    return $self;
}

sub results {
    my $self   = shift;
    my $msm_id = shift;

    my $result;

    croak("You must provide the measurement identificator msm_id (only digits)")
        unless defined $msm_id and $msm_id =~ /^\d+$/;

    return $self->{'_CACHE_MSM'}->{$msm_id}
        if defined $self->{'_CACHE_MSM'}->{$msm_id};

    my $res = $self->{'ua'}->get( $self->{'URL'} .
        "/measurements/$msm_id/results/" .
        '?format=json'
    );

    $self->{'_JSON'} = $res->decoded_content;

    if ($res->is_success) {
        $result = decode_json $res->decoded_content;
    }
    else {
        $result = 'ERROR: ' . $res->status_line;
    }

    $self->{'_CACHE_MSM'}->{$msm_id} = $result;

    return $result;
}

sub json {
    my $self = shift;

    return $self->{'_JSON'};
}

sub answers {
    my $self   = shift;
    my $msm_id = shift;
    my $type = shift;

    $type = 'A' unless $type;

    my $result = results($self, $msm_id);

    my @sal;
    foreach my $resdo (@{$result}) {
        if ($resdo->{'type'} eq 'dns') {
            my $res_set = $resdo->{'resultset'};
            if ($#{$res_set} < 0) {
                push @{$res_set}, $resdo;
            }
            foreach my $dns (@$res_set) {
                my $abuf = $dns->{'result'}->{'abuf'};
                next unless $abuf;
                my $dec_buff = decode_base64 $abuf;
                if(defined $abuf && defined $dec_buff) {
                    my ($dns_pack)= new Net::DNS::Packet(\$dec_buff);
                    my @ans = $dns_pack->answer;
                    foreach my $ans (@ans) {
                        next unless $ans->type eq $type;
                        my $res_ip;
                        if ($type eq 'A') {
                            $res_ip = $ans->address;
                        }
                        elsif ($type eq 'AAAA') {
                            $res_ip = $ans->address_short;
                        }
                        else {
                            $res_ip = $ans->string;
                        }
                        push @sal, $res_ip if $res_ip;
                    }
                }
            }
        }
    }
    return @sal;
}

sub nsids {
    my $self   = shift;
    my $msm_id = shift;

    my $result = results($self, $msm_id);

    my @sal;
    foreach my $resdo (@{$result}) {
        if ($resdo->{'type'} eq 'dns') {
            my $res_set = $resdo->{'resultset'};
            if ($#{$res_set} < 0) {
                push @{$res_set}, $resdo;
            }
            foreach my $dns (@$res_set) {
                my $abuf = $dns->{'result'}->{'abuf'};
                next unless $abuf;
                my $dec_buff = decode_base64 $abuf;
                if(defined $abuf && defined $dec_buff) {
                    my ($dns_pack)= new Net::DNS::Packet(\$dec_buff);
                    my @edns = $dns_pack->edns;
                    foreach my $edn (@edns) {
                        my $res_ip = $edn->option(3);
                        push @sal, ($res_ip ? $res_ip : 'NULL');
                    }
                }
            }
        }
    }
    return @sal;
}

sub rcodes {
    my $self   = shift;
    my $msm_id = shift;

    my $result = results($self, $msm_id);

    my @sal;
    foreach my $resdo (@{$result}) {
        if ($resdo->{'type'} eq 'dns') {
            my $res_set = $resdo->{'resultset'};
            if ($#{$res_set} < 0) {
                push @{$res_set}, $resdo;
            }
            foreach my $dns (@$res_set) {
                my $abuf = $dns->{'result'}->{'abuf'};
                next unless $abuf;
                my $dec_buff = decode_base64 $abuf;
                if(defined $abuf && defined $dec_buff) {
                    my ($dns_pack)= new Net::DNS::Packet(\$dec_buff);
                    my $header = $dns_pack->header;
                    push @sal, $header->rcode;
                }
            }
        }
    }
    return @sal;
}

sub dns {
    my $self = shift;
    my %params = @_;

    croak("You must provide at least the query name")
        unless defined $params{'name'};
    croak('You must provide an API key (KEY constructor param) to create measurements')
        unless defined $self->{'KEY'} and $self->{'KEY'};

    my $qtype = defined($params{'type'}) ? $params{'type'} : 'AAAA';
    my $nprb  = defined($params{'num_prb'}) ? $params{'num_prb'} : 5;

    my %DEFS = (
        description         => 'DNS measurement to ',
        type                => 'dns',
        query_class         => 'IN',
        timeout             => 5000,
        retry               => 0,
        af                  => 4,
        use_macros          => 'false',
        use_probe_resolver  => 'true',
        resolve_on_probe    => 'false',
        set_nsid_bit        => 'true',
        protocol            => 'UDP',
        udp_payload_size    => 1232,
        skip_dns_check      => 'false',
        include_qbuf        => 'false',
        include_abuf        => 'true',
        prepend_probe_id    => 'false',
        set_rd_bit          => 'false',
        set_do_bit          => 'true',
        set_cd_bit          => 'false',
        # start_time
        # stop_time
        # interval
        # target
    );

    my %PROBES = (
        type         => 'area',
        value        => 'WW',
        # tags_include => 'system-ipv4-works,system-can-resolve-a',
        tags_include => 'system-ipv4-works',
    );

    $PROBES{'requested'}    = $nprb;

    $DEFS{'query_argument'} = $params{'name'};
    $DEFS{'query_type'}     = $qtype;
    $DEFS{'description'}   .= $params{'name'};

    my %ATLASCALL;
    push @{$ATLASCALL{'definitions'}}, \%DEFS;
    push @{$ATLASCALL{'probes'}}, \%PROBES;

    $ATLASCALL{'is_oneoff'} = 'true';

    my $json = encode_json \%ATLASCALL;

    my $res = $self->{'ua'}->post( $self->{'URL'} .
        '/measurements/' .
        '?key=' . $self->{'KEY'},
        Content => $json
    );

    if ($res->is_success) {
        my $msmout = $res->decoded_content;
        my $msm = $1 if $res->decoded_content =~ /{"measurements":\[(\d+)\]}/;

        croak 'Bad measurement id, please check: ' . $res->decoded_content unless $msm;

        return $msm;
    }
    else {
        croak 'Could not create a measurement: ' . $res->status_line;
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Net::Magallanes - encapsulation of API calls to RIPE Atlas project.

=head1 SYNOPSIS

  use Net::Magallanes;

  my $atlas = new Net::Magallanes (
      KEY => '<YOUR_API_KEY>'
  );

  my $msm_id = $atlas->dns(
      name    =>  'www.vulcano.cl',
      type    =>  'SRV',
      num_prb =>  10,
  );

  my $result = $atlas->results($msm_id);
  say "Response is ", $result;


=head1 DESCRIPTION

Net::Magallanes is a pure perl interface to the RIPE Atlas API,
for requesting measurements and getting data from past measurements.

More information on RIPE Atlas platform: atlas.ripe.net

=head1 AUTHOR

Hugo Salgado E<lt>hsalgado@vulcano.clE<gt>

=head1 COPYRIGHT

Copyright 2021- Hugo Salgado

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut


