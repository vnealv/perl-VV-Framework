#!/usr/bin/env perl 
use strict;
use warnings;

use utf8;

=encoding UTF8

=head1 NAME

C<vv-start.pl> - bootstrapper script for services to run in container

=head1 SYNOPSIS

perl bin/vv-start.pl -c config_file
Example

    perl bin/vv-start.pl -c /app/opt/config.yml

=head1 DESCRIPTION

This script initializes and run a designated service.
It does this by acquiring the needed configuration along with the intended package to run.
It accepts passed commandline parameters, environemnt variables. prioritised in this order.
Only if not found it will fall to select default values.
After that it invokes the intended package putting it in running state.

=cut

=head1 OPTIONS

=over 4

=item B<-s> I<Service::Example>, B<--service>=I<Service::Example>

Package name of service to be run.

=item B<-t> I<redis://redis:6379>, B<--transport>=I<redis://redis:6379>

Address to the underlying Transport layer URI

=item B<-c> I<1>, B<--redis-cluster>=I<0>

Flag whether we are using Redis cluster or not.

=item B<-l> I</opt/app/lib/>, B<--library>=I</opt/app/lib>

Path to location of service library files.

=item B<-d> I<postgresql>, B<--database>=I<postgresql>

Postgres Database URI.

=back

=cut

use Pod::Usage;
use Getopt::Long;
use Syntax::Keyword::Try;
use YAML::XS;
use Log::Any qw($log);
use Module::Runtime qw(require_module);

use IO::Async::Loop;
use VV::Framework;

GetOptions(
    's|service=s' => \(my $service = $ENV{SERVICE_NAME}), 
    't|transport=s' => \(my $transport_uri = $ENV{TRANSPORT}),
    'c|redis-cluster=s' => \(my $redis_cluster = $ENV{CLUSTER}),
    'l|library=s' => \(my $library_path = $ENV{LIBRARY}),
    'd|database=s' => \(my $db_uri = $ENV{DATABASE}),
    'h|help'     => \my $help,
);

require Log::Any::Adapter;
Log::Any::Adapter->set( qw(Stdout), log_level => "info" );

pod2usage(
    {
        -verbose  => 99,
        -sections => "NAME|SYNOPSIS|DESCRIPTION|OPTIONS",
    }
) if $help;

$db_uri = 'dummy';

my $loop = IO::Async::Loop->new;

# Load passed service.

push @INC, split /,:/, $library_path if $library_path;

if($service =~ /^[a-z0-9_:]+[a-z0-9_]$/i) {
    try {
        require_module($service);
        die 'loaded ' . $service . ' but it cannot ->new?' unless $service->can('new');
    } catch ($e) {
        $log->warnf('Failed to load module for service %s - %s', $service, $e);
    }
} else {
    $log->warnf('unsupported Service name: %s | it should follow package format',  $service);
    die;
}

my $vv = VV::Framework->new(transport => $transport_uri, db => $db_uri, service_name => $service, redis_cluster => $redis_cluster);
$loop->add($vv);

$vv->run->get;



