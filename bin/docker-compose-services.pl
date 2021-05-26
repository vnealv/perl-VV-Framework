#!/usr/bin/env perl 
use strict;
use warnings;

=pod

Populates the C<docker-compose.yml> file with services from the C<services/> directory,
expecting them to be defined as C<category/name> with an optional C<config.yml>

=cut

use Template;
use Path::Tiny;
use YAML::XS qw(LoadFile);
use List::UtilsBy qw(extract_by);

use Log::Any qw($log);
use Log::Any::Adapter qw(Stderr), log_level => 'info';

my $service_dir = path('services');
my @categories = grep { $_->is_dir } $service_dir->children;
my @services;
for my $category (@categories) {
    for my $srv (grep { $_->is_dir } $category->children) {
        my $config_path = $srv->child('config.yml');
        my %args;
        my $path = join '/', 'services', $category->basename, $srv->basename;
        if($srv->child('Dockerfile')->exists) {
            $args{build} = $path;
        } else {
            $args{image} = 'perl:5.26';
        }
        $args{volumes} = ["./$path:/opt/app/", './pg_service.conf:/root/.pg_service.conf:ro'];
        if($config_path->exists) {
            my $cfg = LoadFile($config_path);
            push @services, {
                %args,
                instance => join('_', $category->basename, $_),
                name     => $srv->basename,
                category => $category->basename,
            } for sort keys +($cfg->{instances} || {})->%*;
        } else {
            push @services, {
                %args,
                instance => join('_', $category->basename, $srv->basename),
                name     => $srv->basename,
                category => $category->basename,
            }
        }
    }
}


$log->tracef('- %s', $_) for @services;
$log->infof('%d total services defined', 0 + @services);

my $tt = Template->new;
$tt->process(
    'docker-compose.yml.tt2',
    {
        service_list => \@services,
    },
    'docker-compose.yml'
) or die $tt->error;

