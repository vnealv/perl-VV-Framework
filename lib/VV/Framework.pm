package VV::Framework;

use strict;
use warnings;

our $VERSION = '0.01';

use Object::Pad;

# ABSTRACT: VV microservices framework


class VV::Framework extends IO::Async::Notifier;

use Log::Any qw($log);
use Future::AsyncAwait;

use VV::Framework::Transport::Redis;
use VV::Framework::Transport::Postgres;

has $transport_uri;
has $redis_cluster;
has $db_uri;
has $api;
has $db;

method configure (%args) {
    $transport_uri //= (delete $args{transport} || die 'need a transport uri');
    $db_uri //= (delete $args{db} || die 'need a Database uri');
    $redis_cluster //= delete $args{redis_cluster};
    $self->next::method(%args);
}

method _add_to_loop($loop) {
    $log->tracef('Adding %s to loop', ref $self);
    $self->add_child(
        $api = VV::Framework::Transport::Redis->new(redis_uri => $transport_uri, cluster => $redis_cluster)
    );

    $self->next::method($loop);
}

async method run () {

    await $api->start;
    while (1) {
        $log->warnf('sss running');
        await $self->loop->delay_future(after => 1);
    }

}
1;
