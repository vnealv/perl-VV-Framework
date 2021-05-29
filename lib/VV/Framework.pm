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

has $transport_uri;
has $redis_cluster;
has $db_uri;
has $api;
has $db;
has $service_name;
has $service;
has $app;

method service () { $service; }
method api () { $api; }

method configure (%args) {
    $transport_uri //= (delete $args{transport} || die 'need a transport uri');
    $db_uri //= (delete $args{db} || die 'need a Database uri');
    $redis_cluster //= delete $args{redis_cluster};
    $service //= (delete $args{service} || die 'need a service ');
    $app //= (delete $args{app} || die 'need ann app');
    $service_name = lc(join '_', $app, $service);
    $self->next::method(%args);
}

method _add_to_loop($loop) {
    $log->tracef('Adding %s to loop', ref $self);
    $self->add_child(
        $api = VV::Framework::Transport::Redis->new(redis_uri => $transport_uri, cluster => $redis_cluster,  service_name => $service_name)
    );

    $self->add_child($service = $service->new() );

    $self->next::method($loop);
}

async method run () {

    await $api->start;
    await $self->link_requests;
    await $service->start($api);
    while (1) {
        $log->warnf('sss running');
        await $self->loop->delay_future(after => 1);
    }

}

async method link_requests () {
    my $request_source = $api->subscription_sink->source;
    $request_source->map($self->$curry::weak(async method ($message) {
        try {
            $log->debugf('Received request message %s', $message->as_hash);
            my $method = $message->args->{method};
            if ( defined $method and $service->can($method) ) {
                my $response = await $service->$method($message);
                await $api->reply_success($service_name, $message, $response);
            } else {
                $log->warnf('Error RPC method not found | message: %s', $message);
                await $api->reply_error($service_name, $message, {text => 'NotFound', code => 400});
            }
        } catch ($e) {
            $log->warnf('Error linking request: %s | message: %s', $e, $message);
            await $api->reply_error($service_name, $message, {text => $e, code => 500});
        }
    }))->resolve->completed;
}

1;
