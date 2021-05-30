package VV::Framework;

use strict;
use warnings;

our $VERSION = '0.01';

use Object::Pad;

# ABSTRACT: VV microservices framework


class VV::Framework extends IO::Async::Notifier;

use Log::Any qw($log);
use Syntax::Keyword::Try;
use Future::AsyncAwait;
use curry;

use VV::Framework::Transport::Redis;
use VV::Framework::Transport::Postgres;
use VV::Framework::API;
use VV::Framework::Manager;
use VV::Framework::Storage;

has $transport_uri;
has $redis_cluster;
has $db_uri;
has $api;
has $transport;
has $db;
has $service_name;
has $service;
has $app;
has $manager;
has $storage;

method service () { $service; }
method api () { $api; }

method configure (%args) {
    $transport_uri //= (delete $args{transport} || die 'need a transport uri');
    $db_uri //= (delete $args{db} || die 'need a Database uri');
    $redis_cluster //= delete $args{redis_cluster};
    $service //= (delete $args{service} || die 'need a service ');
    $app //= (delete $args{app} || die 'need ann app');
    $service_name = lc(join '_', map { chomp; $_ } ($app, $service));
    $self->next::method(%args);
}

method _add_to_loop($loop) {
    $self->add_child(
        $transport = VV::Framework::Transport::Redis->new(redis_uri => $transport_uri, cluster => $redis_cluster,  service_name => $service_name)
    );

    $self->add_child(
        $api = VV::Framework::API->new(transport => $transport, service_name => $service_name)
    );
 
    $self->add_child(
        $storage = VV::Framework::Storage->new(transport => $transport, service_name => $service_name)
    );

    $self->add_child($service = $service->new() );

    $manager = VV::Framework::Manager->new(transport => $transport, service => $service, service_name => $service_name);

    $self->next::method($loop);
}

async method run () {

    await $transport->start;
    await $api->start;
    await $manager->link_requests;
    await $storage->start();
    await $service->start($api, $storage);
    while (1) {
        $log->warnf('sss running');
        await $self->loop->delay_future(after => 1);
    }

}

1;
