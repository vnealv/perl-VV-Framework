package VV::Framework::Hook;

use Object::Pad;

class VV::Framework::Hook extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;
use Ryu::Async;
use curry;
use JSON::MaybeUTF8 qw(:v1);
use VV::Framework::Message::Redis;
use VV::Framework::Util qw(subscription_name);

has $ryu;
has $transport;
has $redis;
has $hooks;
has $service_name;

method configure_unknown (%args) {
    $transport = $args{transport};
    $hooks = $args{hooks} //= {};
    $service_name = $args{service_name};
    # Get dedicated redis connection
    $redis = $transport->redis_instance;
}

method _add_to_loop($loop) {
	$self->add_child(
		$ryu = Ryu::Async->new
	);
}

method hooks () { $hooks; }

async method start() {
    await $transport->instance_connect($redis);
}

method redis () { $redis }

async method add_hook ($key, $callback) {
	$log->warnf('sss %s', ref $callback);
    die 'require coderef' unless ref $callback eq 'CODE';
    $hooks->{$key}{callback} = $callback;
	$hooks->{$key}{sink} = $ryu->sink(label => "hook:$key");
    await $self->link_source($key);
	await $self->do_subscribe($key);

}

async method link_source ($key) {
    my $source = $hooks->{$key}{source} = $hooks->{$key}{sink}->source;
	$source->map($self->$curry::weak(async method ($s) {
            $log->warnf('IN SOURCE Map event %s', $s);
		try {
			my $message = decode_json_utf8($s); 
            await $self->hooks->{$key}{callback}->($message);
        } catch ($e) {
			$log->warnf('Could not invoke callback %s | error: %s', $key, $e);
        }
    }))->resolve->completed;
}

async method do_subscribe ($key) {
    $log->warnf('dddd %s', subscription_name($service_name, $key));
	my $sub = await $redis->subscribe(subscription_name($service_name, $key));
    my $subscription = $sub->events->map('payload')->map(sub{
        try {
            my $payload = $_;
            $log->warnf('Received Hook event %s', $payload);
			$hooks->{$key}{sink}->emit($payload);
        } catch ($e) {
            $log->warnf('failed to parse hook event %s | error: %s', $key, $e);
        }
    })->completed;


    await $subscription;
}

1;
