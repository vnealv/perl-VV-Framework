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

=item B<-l> I</opt/app/lib/>, B<--library>=I</opt/app/lib>

Path to location of service library files.

=back

=cut

use Pod::Usage;
use Getopt::Long;
use Syntax::Keyword::Try;
use YAML::XS;
use Log::Any qw($log);

GetOptions(
    'c|config=s'  => \my $config_file,
    's|service=s' => \(my $service_name = $ENV{SERVICE_NAME}), 
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



while (1) {
    $log->infof( '%s', "HI" );
    sleep 1;
}



