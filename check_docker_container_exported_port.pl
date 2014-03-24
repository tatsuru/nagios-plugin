#!/usr/bin/env perl
#
# ./check_docker_process -H docker02 -p 5555 -i repository:5000/image -c 8000
#

use strict;
use warnings;

use Nagios::Plugin;
use LWP::UserAgent;
use URI;
use JSON::XS;
use Net::Ping;
use List::MoreUtils qw(any);


my $plugin = Nagios::Plugin->new(
    usage     => "Usage: %s -H <host> -p <docker_api_port> -i <image> --container_port <container_port> -t <timeout>",
    shortname => "docker container port checker",
);

$plugin->add_arg(
    spec => 'host|H=s',
    help => 'host',
    required => 1,
);

$plugin->add_arg(
    spec => 'port|p=i',
    help => 'docker api port',
    default => 5555,
);

$plugin->add_arg(
    spec => 'image|i=s',
    help => 'image name',
    required => 1,
);

$plugin->add_arg(
    spec => 'container_port|c=i',
    help => 'contaner port',
    required => 1,
);

$plugin->add_arg(
    spec => 'timeout|t=i',
    help => 'timeout',
    default => 3,
);

$plugin->getopts;

my $host           = $plugin->opts->get('host');
my $port           = $plugin->opts->get('port');
my $image          = $plugin->opts->get('image');
my $container_port = $plugin->opts->get('container_port');
my $timeout        = $plugin->opts->get('timeout');

my $containers = get_containers({
    docker_host => $host,
    docker_port => $port,
});
$containers = [
    grep { $_->{Image} =~ /^$image :?/x } @$containers,
];

if (scalar @$containers) {
    my $ping = Net::Ping->new("tcp");
    my $error_containers = [];

    foreach my $container (@$containers) {
        my $ex_ports = get_container_external_ports(+{container => $container, container_port => $container_port});
        if (scalar @$ex_ports) {
            $ping->port_number(@{$ex_ports}[0]);
        }
        else {
            next;                       # not exported
        }
        unless ($ping->ping($host), $timeout) {
            push @$error_containers, $container;
        }
    }
    if (scalar @$error_containers) {
        my $n = scalar @$error_containers;
        $plugin->nagios_exit(CRITICAL, "$n unreachable containers in $image");
    }
    else {
        $plugin->nagios_exit(OK, "all containers reachable.");
    }
}
else {
    $plugin->nagios_exit(OK, "No containers running in $image");
}

sub get_containers {
    my ($args) = @_;
    my $docker_host = $args->{docker_host};
    my $docker_port = $args->{docker_port};
    my $image       = $args->{image};

    my $url = URI->new("http://$docker_host");
    $url->port($docker_port);
    $url->path_query('/containers/json?all=1');
    my $ua  = LWP::UserAgent->new;
    my $res = $ua->get($url);
    my $containers = decode_json($res->decoded_content);
    $containers = [
        grep {
            $_->{Status} =~ /^Up/
        } @$containers,
    ];
    return $containers;
}

sub get_container_external_ports {
    my ($args) = @_;
    my $container = $args->{container};
    my $container_port = $args->{container_port};
    my $ports = $container->{Ports};
    my $ex_ports = [
        grep {
            $_->{PrivatePort} == $container_port
        } @$ports
    ];
    return $ex_ports;
}
