package VV::Framework::API;

use Object::Pad;

class VV::Framework::API extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;

use VV::Framework::Message::Redis;
use VV::Framework::Util qw(whoami);
use curry;

has $transport;
has $responses_subscription_started;
has $pending_requests;
has $service_name;

method configure_unknown (%args) {
    $transport = $args{transport};
    $service_name = $args{service_name}; 
    $pending_requests = {};
}

method responses_subscription_started () {
    # Used to prevent us from sending request before establishing response subscription.
    $responses_subscription_started //= $self->loop->new_future(label => 'responses_subscription');
}

async method start() {
	$self->responses_subscription->retain;
}

async method responses_subscription () {

    my $dedicated_redis = $transport->redis_instance;
    await $transport->instance_connect($dedicated_redis);

	my $sub = await $dedicated_redis->subscribe(whoami());
	my $subscription = $sub->events->map('payload')->map(
        $self->$curry::weak( method ($payload) {
		    try {
                $log->debugf('Received RPC response as %s', $payload);

                my $message = VV::Framework::Message::Redis::from_json($payload);

                if(my $pending = delete $pending_requests->{$message->message_id}) {
                    return $pending->done($message);
                }
                $log->tracef('No pending future for message %s', $message->message_id);
            } catch ($e) {
                $log->warnf('failed to parse rpc response due %s', $e);
            }
        })
    )->completed;

    # Now that we are subscribed, make API ready to send requests.
    $self->responses_subscription_started->done('started');

	await $subscription;
	
}


async method call_rpc($service, %args) {

    # Limit to call services within same app only
    my $stream = join('::', (split('::', $service_name))[0], $service);
    my $pending = $self->loop->new_future(label => "rpc:request:${stream}");
    my $message_id = $transport->next_id;
    my $timeout = delete $args{timeout} || 60;
    my $method = $args{method};
    my $deadline = time + $timeout;

    my $request = VV::Framework::Message::Redis->new(
        rpc        => $method,
        who        => whoami(),
        deadline   => $deadline,
        message_id => $message_id,
        args       => \%args,
    );

    try {
        # make sure we are subscribed first.
        await $self->responses_subscription_started;

        await $transport->redis->xadd($stream => '*', $request->as_hash->%*);

        $log->tracef('Sent RPC request %s', $request->as_hash);
        $pending_requests->{$message_id} = $pending;

        #  responses_subscription will get the message for us
        my $message = await Future->wait_any($self->loop->timeout_future(after => $timeout), $pending)->retain;

        return $message->response;
    } catch ($e) {
        $log->warnf('RPC request failed due: %s', $e);
        $pending->fail($e);
        delete $pending_requests->{$message_id};
    }
}


1;
