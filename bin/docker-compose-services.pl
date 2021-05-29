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

my %default_env = (
    CLUSTER            => "1",
    TRANSPORT          => "redis://redis-node-0:6379",
    LOG_LEVEL          => "info",
    LIBRARY            => "/app/lib",
);

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
            $args{image} = 'perl-vv-framework';
        }
        # pg node name
        $args{pg} = join('-', $category->basename, $srv->basename);
        
        my @service_dir = $srv->child('lib/Service/')->children;
        # At the moment only one Service should be present.
        my ($service_name) = $service_dir[0] =~ /.*\/(.*).pm/m;
        $args{environment}{SERVICE_NAME} = "Service::$service_name";
        $args{environment}{APP} = $category->basename;
        $args{environment}{DATABASE} = $args{pg};

        # Include additional environment variables.
        @{$args{environment}}{keys %default_env} = values %default_env;
        my $env = $srv->child('.env');
        if ( $env->is_file ) {
            my @env = $env->lines_utf8({ chomp => 1 });
            my %env_hash = map { split /=/, $_, 2 } @env;
            @{$args{environment}}{keys %env_hash} = values %env_hash;
        }


        $args{volumes} = ["./$path:/app/", './pg_service.conf:/root/.pg_service.conf:ro'];
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

